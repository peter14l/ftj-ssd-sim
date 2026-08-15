#include "ftj_engine.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>
#include <algorithm>
#include <cstring>
#include <stdexcept>
#include <atomic>
#include <mutex>
#include <vector>

namespace ftj {

// --- LatencyInjector Implementation ---

LatencyInjector::LatencyInjector(uint64_t latency_ns) : latency_ns_(latency_ns) {
    if (!calibrated_) {
        Calibrate();
    }
}

void LatencyInjector::Calibrate() noexcept {
    if (calibrated_) return;

    LARGE_INTEGER freq;
    if (!QueryPerformanceFrequency(&freq)) {
        // Fallback: 3.0 GHz CPU
        cycles_per_ns_ = 3.0;
        calibrated_ = true;
        return;
    }

    LARGE_INTEGER start_qpc, current_qpc;
    QueryPerformanceCounter(&start_qpc);
    uint64_t start_tsc = __rdtsc();

    double elapsed_ms = 0.0;
    const double target_ms = 10.0; // Calibrate over 10 milliseconds

    while (elapsed_ms < target_ms) {
        QueryPerformanceCounter(&current_qpc);
        elapsed_ms = static_cast<double>(current_qpc.QuadPart - start_qpc.QuadPart) * 1000.0 / freq.QuadPart;
    }

    uint64_t end_tsc = __rdtsc();
    double total_ns = elapsed_ms * 1'000'000.0;
    cycles_per_ns_ = static_cast<double>(end_tsc - start_tsc) / total_ns;

    // Ensure we have a sane value
    if (cycles_per_ns_ <= 0.1) {
        cycles_per_ns_ = 3.0;
    }

    calibrated_ = true;
}

void LatencyInjector::Inject() const noexcept {
    if (latency_ns_ == 0) return;

    uint64_t start = __rdtsc();
    uint64_t target_cycles = static_cast<uint64_t>(latency_ns_ * cycles_per_ns_);
    
    while ((__rdtsc() - start) < target_cycles) {
        #if defined(_M_IX86) || defined(_M_X64)
        _mm_pause();
        #endif
    }
}

double LatencyInjector::GetCyclesPerNs() noexcept {
    if (!calibrated_) {
        Calibrate();
    }
    return cycles_per_ns_;
}

static thread_local uint64_t g_seed = 1337;

// Extremely simple, fast, thread-safe pseudo-random number generator
static uint64_t SimpleRand(uint64_t& seed) noexcept {
    seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
    return seed;
}

// --- FTJController Implementation ---

FTJController::FTJController(size_t capacity_bytes, uint64_t latency_ns)
    : capacity_(capacity_bytes), latency_ns_(latency_ns), injector_(latency_ns) {
    
    // Allocate the virtual memory buffer
    memory_buffer_ = std::make_unique<uint8_t[]>(capacity_);
    std::fill_n(memory_buffer_.get(), capacity_, uint8_t{0});

    // Allocate the ECC buffer (1 byte of ECC per 8 bytes of data)
    size_t ecc_size = (capacity_bytes + 7) / 8;
    ecc_buffer_ = std::make_unique<uint8_t[]>(ecc_size);
    std::fill_n(ecc_buffer_.get(), ecc_size, uint8_t{0});

    // Initialize page writes (per 4KB page) - allocate atomic array
    size_t num_pages = (capacity_bytes + PAGE_SIZE - 1) / PAGE_SIZE;
    page_writes_.reset(new std::atomic<uint32_t>[num_pages]);
    page_count_ = num_pages;
    for (size_t i = 0; i < num_pages; ++i) page_writes_[i].store(0, std::memory_order_relaxed);

    // Initialize simple FTL structures
    num_blocks_ = static_cast<size_t>(num_pages / PAGES_PER_BLOCK);
    if (num_blocks_ == 0) num_blocks_ = 1;
    l2p_map_.assign(page_count_, -1);
    phys_valid_.assign(page_count_, 0);
    phys_owner_lba_.assign(page_count_, -1);
    phys_block_.resize(page_count_);
    for (size_t p = 0; p < page_count_; ++p) phys_block_[p] = static_cast<int32_t>(p / PAGES_PER_BLOCK);
    block_valid_count_.assign(num_blocks_, 0);

    // LBA hot counters
    lba_hot_counters_.assign(page_count_, 0);

    // Split free pages into hot/cold zones: reserve first 20% blocks for hot region
    size_t hot_blocks = std::max<size_t>(1, num_blocks_ / 5);
    free_physical_pages_hot_.reserve(page_count_ / 4);
    free_physical_pages_cold_.reserve(page_count_);

    for (int32_t p = static_cast<int32_t>(page_count_) - 1; p >= 0; --p) {
        int32_t b = phys_block_[p];
        if (static_cast<size_t>(b) < hot_blocks) {
            free_physical_pages_hot_.push_back(p);
        } else {
            free_physical_pages_cold_.push_back(p);
        }
    }

    // GC thresholds: trigger when free pages < 5% of total, aim to free up to 10%
    gc_low_watermark_ = std::max<size_t>(1, page_count_ / 20);
    gc_target_free_ = std::max<size_t>(1, page_count_ / 10);

    total_physical_bytes_written_.store(0, std::memory_order_relaxed);
}

FTJController::~FTJController() = default;

uint8_t FTJController::CalculateECC(uint64_t data) noexcept {
    uint8_t ecc = 0;
    for (int i = 0; i < 7; ++i) {
        uint64_t mask = 0;
        for (int d = 0; d < 64; ++d) {
            int code_idx = d + 1;
            if (code_idx >= 1) code_idx++;
            if (code_idx >= 2) code_idx++;
            if (code_idx >= 4) code_idx++;
            if (code_idx >= 8) code_idx++;
            if (code_idx >= 16) code_idx++;
            if (code_idx >= 32) code_idx++;
            if (code_idx >= 64) code_idx++;
            
            if ((code_idx & (1 << i)) != 0) {
                mask |= (1ULL << d);
            }
        }
        uint64_t val = data & mask;
        // Count set bits parity
        #ifdef _MSC_VER
        uint8_t p = static_cast<uint8_t>(__popcnt64(val) & 1);
        #else
        uint8_t p = static_cast<uint8_t>(__builtin_parityll(val));
        #endif
        ecc |= (p << i);
    }
    
    // 8th bit is overall parity
    #ifdef _MSC_VER
    uint8_t overall = static_cast<uint8_t>((__popcnt64(data) + __popcnt(ecc)) & 1);
    #else
    uint8_t overall = static_cast<uint8_t>((__builtin_parityll(data) + __builtin_parity(ecc)) & 1);
    #endif
    ecc |= (overall << 7);
    
    return ecc;
}

int FTJController::DecodeAndCorrect(uint64_t& data, uint8_t stored_ecc) noexcept {
    uint8_t calculated_ecc = CalculateECC(data);
    uint8_t syndrome = (calculated_ecc ^ stored_ecc) & 0x7F;
    uint8_t overall_parity = (calculated_ecc ^ stored_ecc) & 0x80;
    
    if (syndrome == 0 && overall_parity == 0) {
        return 0; // No error
    }
    
    if (overall_parity != 0) {
        int error_pos = syndrome;
        int data_bit = -1;
        for (int d = 0; d < 64; ++d) {
            int code_idx = d + 1;
            if (code_idx >= 1) code_idx++;
            if (code_idx >= 2) code_idx++;
            if (code_idx >= 4) code_idx++;
            if (code_idx >= 8) code_idx++;
            if (code_idx >= 16) code_idx++;
            if (code_idx >= 32) code_idx++;
            if (code_idx >= 64) code_idx++;
            
            if (code_idx == error_pos) {
                data_bit = d;
                break;
            }
        }
        
        if (data_bit != -1) {
            data ^= (1ULL << data_bit);
            return 1; // Corrected
        }
        return 1; // Corrected parity bit itself
    } else {
        return 2; // Uncorrectable double-bit error
    }
}

double FTJController::GetMaxWearPercentage() const noexcept {
    if (page_count_ == 0) return 0.0;
    uint32_t max_w = 0;
    for (size_t i = 0; i < page_count_; ++i) {
        uint32_t w = page_writes_[i].load(std::memory_order_relaxed);
        if (w > max_w) max_w = w;
    }
    return (static_cast<double>(max_w) / WEAR_THRESHOLD) * 100.0;
}

uint64_t FTJController::GetTotalPhysicalBytesWritten() const noexcept {
    return total_physical_bytes_written_.load(std::memory_order_relaxed);
}

void FTJController::InjectHeavyWear(uint64_t offset, uint32_t write_count) noexcept {
    uint64_t page = offset / 4096;
    if (page < page_count_) {
        page_writes_[page].store(write_count, std::memory_order_relaxed);
    }
}

bool FTJController::Read(uint64_t offset, void* dest, size_t size) const noexcept {
    if (!dest || size > capacity_ || offset > capacity_ - size) {
        return false;
    }

    // Inject exact simulated latency
    injector_.Inject();

    uint8_t* dest_bytes = static_cast<uint8_t*>(dest);
    size_t dest_offset = 0;
    bool success = true;

    uint64_t start_byte = offset;
    uint64_t end_byte = offset + size;

    std::lock_guard<std::mutex> lg(mapping_mutex_);

    while (start_byte < end_byte) {
        uint64_t lp = start_byte / PAGE_SIZE; // logical page
        uint64_t page_offset = start_byte % PAGE_SIZE;
        uint64_t to_copy = std::min(end_byte - start_byte, static_cast<uint64_t>(PAGE_SIZE - page_offset));

        int32_t phys = (lp < l2p_map_.size()) ? l2p_map_[lp] : -1;
        if (phys == -1) {
            // unmapped reads return zeros
            for (uint64_t i = 0; i < to_copy; ++i) dest_bytes[dest_offset++] = 0;
        } else {
            // For ECC and bitflip simulation we iterate per 8-byte chunk within this region
            uint64_t chunk_start = (static_cast<uint64_t>(phys) * PAGE_SIZE + page_offset) / 8;
            uint64_t chunk_end = (static_cast<uint64_t>(phys) * PAGE_SIZE + page_offset + to_copy - 1) / 8;

            for (uint64_t chunk = chunk_start; chunk <= chunk_end; ++chunk) {
                uint64_t chunk_offset = chunk * 8;
                uint64_t local_offset = chunk_offset - static_cast<uint64_t>(phys) * PAGE_SIZE;
                uint64_t start_b = (local_offset < page_offset) ? page_offset : local_offset;
                uint64_t end_b = std::min<uint64_t>(local_offset + 8, page_offset + to_copy);

                uint64_t data_word = 0;
                std::memcpy(&data_word, memory_buffer_.get() + static_cast<size_t>(phys) * PAGE_SIZE + local_offset, 8);
                uint8_t stored_ecc = ecc_buffer_[(static_cast<size_t>(phys) * PAGE_SIZE + local_offset) / 8];

                uint32_t writes = page_writes_[phys].load(std::memory_order_relaxed);
                if (writes > WEAR_THRESHOLD) {
                    double prob = static_cast<double>(writes - WEAR_THRESHOLD) / WEAR_THRESHOLD * 0.05;
                    double rand_val = static_cast<double>(SimpleRand(g_seed) % 10000) / 10000.0;
                    if (rand_val < prob) {
                        int bit1 = SimpleRand(g_seed) % 64;
                        data_word ^= (1ULL << bit1);
                        total_bit_flips_.fetch_add(1, std::memory_order_relaxed);
                        double rand_val2 = static_cast<double>(SimpleRand(g_seed) % 10000) / 10000.0;
                        if (rand_val2 < 0.20) {
                            int bit2 = SimpleRand(g_seed) % 64;
                            while (bit2 == bit1) bit2 = SimpleRand(g_seed) % 64;
                            data_word ^= (1ULL << bit2);
                            total_bit_flips_.fetch_add(1, std::memory_order_relaxed);
                        }
                    }
                }

                int err = DecodeAndCorrect(data_word, stored_ecc);
                if (err == 1) corrected_errors_.fetch_add(1, std::memory_order_relaxed);
                else if (err == 2) { uncorrectable_errors_.fetch_add(1, std::memory_order_relaxed); success = false; }

                const uint8_t* word_bytes = reinterpret_cast<const uint8_t*>(&data_word);
                for (uint64_t b = start_b; b < end_b; ++b) {
                    dest_bytes[dest_offset++] = word_bytes[b - local_offset];
                }
            }
        }

        start_byte += to_copy;
    }

    total_reads_.fetch_add(1, std::memory_order_relaxed);
    return success;
}

bool FTJController::Write(uint64_t offset, const void* src, size_t size) noexcept {
    if (!src || size > capacity_ || offset > capacity_ - size) {
        return false;
    }

    // Inject exact simulated latency
    injector_.Inject();

    const uint8_t* src_bytes = static_cast<const uint8_t*>(src);
    uint64_t start_byte = offset;
    uint64_t end_byte = offset + size;
    size_t written_logical = 0;

    std::lock_guard<std::mutex> lg(mapping_mutex_);

    while (start_byte < end_byte) {
        uint64_t lp = start_byte / PAGE_SIZE;
        uint64_t page_offset = start_byte % PAGE_SIZE;
        uint64_t to_write = std::min(end_byte - start_byte, static_cast<uint64_t>(PAGE_SIZE - page_offset));

        // Update hot counter for this logical page
        if (lp < lba_hot_counters_.size()) {
            lba_hot_counters_[lp] = std::min<uint32_t>(UINT32_MAX, lba_hot_counters_[lp] + 1);
        }
        bool prefer_hot = (lp < lba_hot_counters_.size()) && (lba_hot_counters_[lp] >= HOT_THRESHOLD);

        // Allocate a new physical page (prefer hot or cold based on LBA)
        int32_t new_phys = AllocatePhysicalPage(prefer_hot);
        if (new_phys < 0) {
            // Attempt GC once
            RunGC(gc_target_free_);
            new_phys = AllocatePhysicalPage(prefer_hot);
            if (new_phys < 0) return false; // out of space
        }

        // Copy old data if present
        int32_t old_phys = (lp < l2p_map_.size()) ? l2p_map_[lp] : -1;
        if (old_phys >= 0) {
            std::memcpy(memory_buffer_.get() + static_cast<size_t>(new_phys) * PAGE_SIZE,
                       memory_buffer_.get() + static_cast<size_t>(old_phys) * PAGE_SIZE,
                       PAGE_SIZE);
            // copy ECC for page
            size_t chunk_start = (static_cast<size_t>(new_phys) * PAGE_SIZE) / 8;
            size_t old_chunk_start = (static_cast<size_t>(old_phys) * PAGE_SIZE) / 8;
            for (size_t c = 0; c < PAGE_SIZE / 8; ++c) {
                ecc_buffer_[chunk_start + c] = ecc_buffer_[old_chunk_start + c];
            }
        } else {
            // zero fill
            std::memset(memory_buffer_.get() + static_cast<size_t>(new_phys) * PAGE_SIZE, 0, PAGE_SIZE);
            size_t chunk_start = (static_cast<size_t>(new_phys) * PAGE_SIZE) / 8;
            for (size_t c = 0; c < PAGE_SIZE / 8; ++c) ecc_buffer_[chunk_start + c] = 0;
        }

        // Perform the actual write into new physical page
        uint8_t* dest_ptr = memory_buffer_.get() + static_cast<size_t>(new_phys) * PAGE_SIZE + page_offset;
        std::memcpy(dest_ptr, src_bytes + written_logical, static_cast<size_t>(to_write));

        // Recompute ECC for affected chunks in the page
        size_t first_chunk = (static_cast<size_t>(new_phys) * PAGE_SIZE + page_offset) / 8;
        size_t last_chunk = (static_cast<size_t>(new_phys) * PAGE_SIZE + page_offset + to_write - 1) / 8;
        for (size_t c = first_chunk; c <= last_chunk; ++c) {
            uint64_t data_word = 0;
            std::memcpy(&data_word, memory_buffer_.get() + c * 8, 8);
            ecc_buffer_[c] = CalculateECC(data_word);
        }

        // Update mapping
        l2p_map_[lp] = new_phys;
        phys_valid_[new_phys] = 1;
        phys_owner_lba_[new_phys] = static_cast<int32_t>(lp);
        block_valid_count_[phys_block_[new_phys]]++;
        page_writes_[new_phys].fetch_add(1, std::memory_order_relaxed);
        total_physical_bytes_written_.fetch_add(PAGE_SIZE, std::memory_order_relaxed);

        // Old physical page becomes invalid (not immediately freed until GC)
        if (old_phys >= 0) {
            phys_valid_[old_phys] = 0;
            phys_owner_lba_[old_phys] = -1;
            block_valid_count_[phys_block_[old_phys]] = std::max(0, block_valid_count_[phys_block_[old_phys]] - 1);
            // do not push to free list here
        }

        start_byte += to_write;
        written_logical += static_cast<size_t>(to_write);
    }

    total_writes_.fetch_add(1, std::memory_order_relaxed);

    // Trigger GC if needed (sum of hot+cold free pages)
    if ((free_physical_pages_hot_.size() + free_physical_pages_cold_.size()) < gc_low_watermark_) {
        RunGC(gc_target_free_);
    }

    return true;
}


int32_t FTJController::AllocatePhysicalPage(bool prefer_hot) noexcept {
    // Try preferred zone first
    if (prefer_hot) {
        if (!free_physical_pages_hot_.empty()) {
            int32_t p = free_physical_pages_hot_.back();
            free_physical_pages_hot_.pop_back();
            return p;
        }
        if (!free_physical_pages_cold_.empty()) {
            int32_t p = free_physical_pages_cold_.back();
            free_physical_pages_cold_.pop_back();
            return p;
        }
        return -1;
    } else {
        if (!free_physical_pages_cold_.empty()) {
            int32_t p = free_physical_pages_cold_.back();
            free_physical_pages_cold_.pop_back();
            return p;
        }
        if (!free_physical_pages_hot_.empty()) {
            int32_t p = free_physical_pages_hot_.back();
            free_physical_pages_hot_.pop_back();
            return p;
        }
        return -1;
    }
}

void FTJController::RunGC(size_t target_free) noexcept {
    // Hot/cold-aware GC: prefer blocks with low hotness and low valid count
    while ((free_physical_pages_hot_.size() + free_physical_pages_cold_.size()) < target_free) {
        int candidate = -1;
        int best_metric = INT_MAX;

        // compute block hotness score
        for (size_t b = 0; b < block_valid_count_.size(); ++b) {
            int valid = block_valid_count_[b];
            int hot_score = 0;
            size_t start_p = b * PAGES_PER_BLOCK;
            size_t end_p = std::min(page_count_, start_p + PAGES_PER_BLOCK);
            for (size_t p = start_p; p < end_p; ++p) {
                int owner = phys_owner_lba_[p];
                if (owner >= 0 && static_cast<size_t>(owner) < lba_hot_counters_.size()) {
                    hot_score += static_cast<int>(lba_hot_counters_[owner]);
                }
            }
            int metric = valid * 16 + hot_score; // weight valid pages higher
            if (metric < best_metric) { best_metric = metric; candidate = static_cast<int>(b); }
        }

        if (candidate == -1) break;

        // Move valid pages out of the block
        size_t start_p = static_cast<size_t>(candidate) * PAGES_PER_BLOCK;
        size_t end_p = std::min(page_count_, start_p + PAGES_PER_BLOCK);
        for (size_t p = start_p; p < end_p; ++p) {
            if (phys_valid_[p]) {
                int owner = phys_owner_lba_[p];
                // allocate target page; prefer cold for GC migrations to group cold pages
                int32_t new_p = AllocatePhysicalPage(false);
                if (new_p < 0) {
                    // no free page - try next block or exit
                    continue;
                }
                // copy data and ECC
                std::memcpy(memory_buffer_.get() + static_cast<size_t>(new_p) * PAGE_SIZE,
                           memory_buffer_.get() + static_cast<size_t>(p) * PAGE_SIZE,
                           PAGE_SIZE);
                size_t old_chunk_start = (static_cast<size_t>(p) * PAGE_SIZE) / 8;
                size_t new_chunk_start = (static_cast<size_t>(new_p) * PAGE_SIZE) / 8;
                for (size_t c = 0; c < PAGE_SIZE / 8; ++c) {
                    ecc_buffer_[new_chunk_start + c] = ecc_buffer_[old_chunk_start + c];
                }

                // update mapping
                if (owner >= 0 && static_cast<size_t>(owner) < l2p_map_.size()) {
                    l2p_map_[owner] = new_p;
                    phys_owner_lba_[new_p] = owner;
                    phys_valid_[new_p] = 1;
                    block_valid_count_[phys_block_[new_p]]++;
                    page_writes_[new_p].fetch_add(1, std::memory_order_relaxed);
                    total_physical_bytes_written_.fetch_add(PAGE_SIZE, std::memory_order_relaxed);

                    // invalidate old
                    phys_valid_[p] = 0;
                    phys_owner_lba_[p] = -1;
                    block_valid_count_[phys_block_[p]] = std::max(0, block_valid_count_[phys_block_[p]] - 1);
                    // old page will be reclaimed below
                }
            }
        }

        // Erase block: mark pages free and push to appropriate hot/cold free lists
        for (size_t p = start_p; p < end_p; ++p) {
            if (phys_valid_[p]) {
                // if still valid (couldn't move), skip
                continue;
            }
            phys_valid_[p] = 0;
            phys_owner_lba_[p] = -1;
            int b = phys_block_[p];
            if (static_cast<size_t>(b) < (num_blocks_ / 5)) {
                free_physical_pages_hot_.push_back(static_cast<int32_t>(p));
            } else {
                free_physical_pages_cold_.push_back(static_cast<int32_t>(p));
            }
        }

        block_valid_count_[candidate] = 0;

        // If GC couldn't free pages (no candidate), break
        if ((free_physical_pages_hot_.size() + free_physical_pages_cold_.size()) >= target_free) break;
        // else continue to next iteration
    }
}

} // namespace ftj


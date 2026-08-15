#include "ftj_engine.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>
#include <algorithm>
#include <cstring>
#include <stdexcept>
#include <atomic>

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

    // Initialize page writes (per 4KB page)
    size_t num_pages = (capacity_bytes + 4095) / 4096;
    page_writes_.resize(num_pages);
    for (size_t i = 0; i < num_pages; ++i) page_writes_[i].store(0, std::memory_order_relaxed);
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
    if (page_writes_.empty()) return 0.0;
    uint32_t max_w = 0;
    for (size_t i = 0; i < page_writes_.size(); ++i) {
        uint32_t w = page_writes_[i].load(std::memory_order_relaxed);
        if (w > max_w) max_w = w;
    }
    return (static_cast<double>(max_w) / WEAR_THRESHOLD) * 100.0;
}

void FTJController::InjectHeavyWear(uint64_t offset, uint32_t write_count) noexcept {
    uint64_t page = offset / 4096;
    if (page < page_writes_.size()) {
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

    uint64_t start_chunk = offset / 8;
    uint64_t end_chunk = (offset + size - 1) / 8;

    for (uint64_t chunk = start_chunk; chunk <= end_chunk; ++chunk) {
        uint64_t chunk_offset = chunk * 8;
        
        uint64_t data_word = 0;
        std::memcpy(&data_word, memory_buffer_.get() + chunk_offset, 8);
        uint8_t stored_ecc = ecc_buffer_[chunk];

        // Simulate bit degradation based on page wear
        uint64_t page = chunk_offset / 4096;
        uint32_t writes = (page < page_writes_.size()) ? page_writes_[page].load(std::memory_order_relaxed) : 0;

        if (writes > WEAR_THRESHOLD) {
            double prob = static_cast<double>(writes - WEAR_THRESHOLD) / WEAR_THRESHOLD * 0.05; // up to 5%
            
            // Random injection
            double rand_val = static_cast<double>(SimpleRand(g_seed) % 10000) / 10000.0;
            if (rand_val < prob) {
                // Flip 1 bit
                int bit1 = SimpleRand(g_seed) % 64;
                data_word ^= (1ULL << bit1);
                total_bit_flips_.fetch_add(1, std::memory_order_relaxed);

                // 20% chance of double bit flip (uncorrectable)
                double rand_val2 = static_cast<double>(SimpleRand(g_seed) % 10000) / 10000.0;
                if (rand_val2 < 0.20) {
                    int bit2 = SimpleRand(g_seed) % 64;
                    while (bit2 == bit1) {
                        bit2 = SimpleRand(g_seed) % 64;
                    }
                    data_word ^= (1ULL << bit2);
                    total_bit_flips_.fetch_add(1, std::memory_order_relaxed);
                }
            }
        }

        // Validate and correct
        int err = DecodeAndCorrect(data_word, stored_ecc);
        if (err == 1) {
            corrected_errors_.fetch_add(1, std::memory_order_relaxed);
        } else if (err == 2) {
            uncorrectable_errors_.fetch_add(1, std::memory_order_relaxed);
            success = false;
        }

        // Copy matching bytes to destination
        uint64_t start_byte = (offset > chunk_offset) ? (offset - chunk_offset) : 0;
        uint64_t end_byte = ((offset + size) < (chunk_offset + 8)) ? ((offset + size) - chunk_offset) : 8;

        const uint8_t* word_bytes = reinterpret_cast<const uint8_t*>(&data_word);
        for (uint64_t b = start_byte; b < end_byte; ++b) {
            dest_bytes[dest_offset++] = word_bytes[b];
        }
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
    size_t src_offset = 0;

    uint64_t start_chunk = offset / 8;
    uint64_t end_chunk = (offset + size - 1) / 8;

    for (uint64_t chunk = start_chunk; chunk <= end_chunk; ++chunk) {
        uint64_t chunk_offset = chunk * 8;
        
        // Read existing 8-byte word (needed if write is unaligned/partial)
        uint64_t data_word = 0;
        std::memcpy(&data_word, memory_buffer_.get() + chunk_offset, 8);

        // Update the bytes being written
        uint64_t start_byte = (offset > chunk_offset) ? (offset - chunk_offset) : 0;
        uint64_t end_byte = ((offset + size) < (chunk_offset + 8)) ? ((offset + size) - chunk_offset) : 8;

        uint8_t* word_bytes = reinterpret_cast<uint8_t*>(&data_word);
        for (uint64_t b = start_byte; b < end_byte; ++b) {
            word_bytes[b] = src_bytes[src_offset++];
        }

        // Store back in buffer
        std::memcpy(memory_buffer_.get() + chunk_offset, &data_word, 8);

        // Compute and store ECC
        ecc_buffer_[chunk] = CalculateECC(data_word);

        // Update page write count
        uint64_t page = chunk_offset / 4096;
        if (page < page_writes_.size()) {
            page_writes_[page].fetch_add(1, std::memory_order_relaxed);
        }
    }

    total_writes_.fetch_add(1, std::memory_order_relaxed);
    return true;
}

} // namespace ftj

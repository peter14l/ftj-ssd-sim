#include "ftj_engine.hpp"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>
#else
#include <x86intrin.h>
#include <immintrin.h>
#include <chrono>
#endif

#include <algorithm>
#include <cmath>
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

#ifdef _WIN32
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
#else
    auto start_time = std::chrono::high_resolution_clock::now();
    uint64_t start_tsc = __rdtsc();

    double elapsed_ms = 0.0;
    const double target_ms = 10.0; // Calibrate over 10 milliseconds

    while (elapsed_ms < target_ms) {
        auto current_time = std::chrono::high_resolution_clock::now();
        elapsed_ms = std::chrono::duration<double, std::milli>(current_time - start_time).count();
    }

    uint64_t end_tsc = __rdtsc();
    double total_ns = elapsed_ms * 1'000'000.0;
    cycles_per_ns_ = static_cast<double>(end_tsc - start_tsc) / total_ns;
#endif

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
        #if defined(_M_IX86) || defined(_M_X64) || defined(__i386__) || defined(__x86_64__)
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
    page_disturbs_.reset(new std::atomic<uint32_t>[num_pages]);
    page_count_ = num_pages;
    for (size_t i = 0; i < num_pages; ++i) {
        page_writes_[i].store(0, std::memory_order_relaxed);
        page_disturbs_[i].store(0, std::memory_order_relaxed);
    }

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

void FTJController::SetPhysicsConfig(const CrossbarPhysicsConfig& config) noexcept {
    std::lock_guard<std::mutex> lock(physics_mutex_);
    physics_cfg_ = config;
}

FTJController::CrossbarPhysicsConfig FTJController::GetPhysicsConfig() const noexcept {
    std::lock_guard<std::mutex> lock(physics_mutex_);
    return physics_cfg_;
}

double FTJController::CalculateTERRatio(double temperature_c) const noexcept {
    // Ferroelectric polarization decreases with temperature up to Curie temperature (Tc ~ 450C for HfO2)
    // TER = (R_HRS - R_LRS) / R_LRS. At 25C TER ~ 50x. At 125C, TER compresses to ~18x.
    double temp_clamped = std::clamp(temperature_c, 0.0, 150.0);
    double degradation_factor = 1.0 - (temp_clamped - 25.0) * 0.0065;
    if (degradation_factor < 0.2) degradation_factor = 0.2;
    
    double nominal_ter = (physics_cfg_.r_hrs_nominal_ohm - physics_cfg_.r_lrs_nominal_ohm) / physics_cfg_.r_lrs_nominal_ohm;
    return nominal_ter * degradation_factor;
}

double FTJController::CalculateEffectiveVoltage(uint64_t offset, bool is_write) const noexcept {
    if (!physics_cfg_.enable_ir_drop_sim) {
        return is_write ? physics_cfg_.v_applied_write : physics_cfg_.v_applied_read;
    }

    // Map offset to synthetic 2D crossbar sub-array coordinates (e.g. 512 x 512 bitcell sub-arrays)
    constexpr uint32_t ARRAY_DIM = 512;
    uint32_t cell_idx = static_cast<uint32_t>((offset / 8) % (ARRAY_DIM * ARRAY_DIM));
    uint32_t row_x = cell_idx % ARRAY_DIM;
    uint32_t col_y = cell_idx / ARRAY_DIM;

    double v_applied = is_write ? physics_cfg_.v_applied_write : physics_cfg_.v_applied_read;

    // Estimate sneak path leakage current through unselected cells mediated by 1S-1R selector
    double unselected_cell_leakage = (v_applied / 2.0) / (physics_cfg_.r_hrs_nominal_ohm * physics_cfg_.selector_nonlinearity);
    double total_line_current = (v_applied / physics_cfg_.r_lrs_nominal_ohm) + (unselected_cell_leakage * ARRAY_DIM);

    // Cumulative wire resistance along Word-Line (row_x) and Bit-Line (col_y)
    double r_total_wire = (row_x * physics_cfg_.r_wire_wl_ohm) + (col_y * physics_cfg_.r_wire_bl_ohm);
    double ir_drop_volts = total_line_current * r_total_wire;

    // Clamp drop to avoid inversion
    if (ir_drop_volts > v_applied * 0.35) {
        ir_drop_volts = v_applied * 0.35;
    }

    double ir_drop_mv = ir_drop_volts * 1000.0;
    double prev_max = max_observed_ir_drop_mv_.load(std::memory_order_relaxed);
    while (ir_drop_mv > prev_max && !max_observed_ir_drop_mv_.compare_exchange_weak(prev_max, ir_drop_mv, std::memory_order_relaxed)) {}

    return std::max(0.1, v_applied - ir_drop_volts);
}

double FTJController::CalculateMerzSwitchingLatency(double v_eff_volts, bool is_write) const noexcept {
    // Merz's Law: tau = tau_0 * exp(alpha * Activation_Field / V_effective)
    // As V_effective drops due to IR drop, switching latency increases exponentially.
    double base_latency = is_write ? 300.0 : 8.0; // ns
    double v_nominal = is_write ? physics_cfg_.v_applied_write : physics_cfg_.v_applied_read;
    
    if (v_eff_volts >= v_nominal) {
        return base_latency;
    }

    double delta_ratio = (v_nominal / v_eff_volts) - 1.0;
    double penalty = std::exp(physics_cfg_.alpha_activation * delta_ratio);
    return base_latency * penalty;
}

FTJController::PhysicsTelemetry FTJController::GetPhysicsTelemetry() const noexcept {
    PhysicsTelemetry tel;
    tel.max_ir_drop_mv = max_observed_ir_drop_mv_.load(std::memory_order_relaxed);
    tel.current_temperature_c = physics_cfg_.ambient_temp_c;
    tel.min_ter_ratio = CalculateTERRatio(tel.current_temperature_c);
    
    uint64_t ops = total_switching_ops_.load(std::memory_order_relaxed);
    uint64_t accum = total_switching_latency_accum_ns_.load(std::memory_order_relaxed);
    tel.avg_switching_latency_ns = (ops > 0) ? (static_cast<double>(accum) / ops) : static_cast<double>(latency_ns_);
    
    tel.total_half_select_disturbs = total_half_select_disturbs_.load(std::memory_order_relaxed);
    tel.total_autonomous_refreshes = total_autonomous_refreshes_.load(std::memory_order_relaxed);
    return tel;
}

uint64_t FTJController::TriggerAutonomousRefresh() noexcept {
    uint64_t refreshed_pages = 0;
    for (size_t p = 0; p < page_count_; ++p) {
        uint32_t disturbs = page_disturbs_[p].load(std::memory_order_relaxed);
        if (disturbs > 0) {
            page_disturbs_[p].store(0, std::memory_order_relaxed);
            refreshed_pages++;
        }
    }
    total_autonomous_refreshes_.fetch_add(refreshed_pages, std::memory_order_relaxed);
    return refreshed_pages;
}

void FTJController::SimulateRetentionDrift(double elapsed_hours, double temperature_c) noexcept {
    // Arrhenius retention relaxation model: Tau_retention(T) = Tau_0 * exp(E_a / (k_B * T))
    // Accelerated high-temperature baking increases bit flip probability
    double t_kelvin = temperature_c + 273.15;
    constexpr double k_b = 8.617333e-5; // eV/K
    constexpr double e_a = 1.1;         // Activation energy for HfO2 polarization relaxation (~1.1 eV)
    
    double thermal_rate = std::exp(-e_a / (k_b * t_kelvin));
    double drift_prob = 1.0 - std::exp(-thermal_rate * elapsed_hours * 3600.0 * 1e8);
    drift_prob = std::clamp(drift_prob, 0.0, 0.08); // Maximum 8% bit degradation under extreme stress

    for (size_t p = 0; p < page_count_; ++p) {
        if (phys_valid_[p]) {
            double rand_val = static_cast<double>(SimpleRand(g_seed) % 10000) / 10000.0;
            if (rand_val < drift_prob) {
                // Introduce bit-flip into physical page
                size_t byte_pos = static_cast<size_t>(p * PAGE_SIZE + (SimpleRand(g_seed) % PAGE_SIZE));
                memory_buffer_[byte_pos] ^= (1 << (SimpleRand(g_seed) % 8));
                total_bit_flips_.fetch_add(1, std::memory_order_relaxed);
            }
        }
    }
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

    // Compute physics-accurate effective voltage and switching latency
    double v_eff = CalculateEffectiveVoltage(offset, false);
    double dynamic_latency_ns = CalculateMerzSwitchingLatency(v_eff, false);
    
    total_switching_latency_accum_ns_.fetch_add(static_cast<uint64_t>(dynamic_latency_ns), std::memory_order_relaxed);
    total_switching_ops_.fetch_add(1, std::memory_order_relaxed);

    // Inject simulated latency
    if (dynamic_latency_ns > latency_ns_) {
        LatencyInjector dynamic_injector(static_cast<uint64_t>(dynamic_latency_ns));
        dynamic_injector.Inject();
    } else {
        injector_.Inject();
    }

    uint8_t* dest_bytes = static_cast<uint8_t*>(dest);
    uint64_t start_byte = offset;
    uint64_t end_byte = offset + size;
    size_t dest_offset = 0;
    bool success = true;

    std::lock_guard<std::mutex> lg(mapping_mutex_);

    while (start_byte < end_byte) {
        uint64_t lp = start_byte / PAGE_SIZE;
        uint64_t page_offset = start_byte % PAGE_SIZE;
        uint64_t to_copy = std::min(end_byte - start_byte, static_cast<uint64_t>(PAGE_SIZE - page_offset));

        int32_t phys = (lp < l2p_map_.size()) ? l2p_map_[lp] : -1;
        if (phys < 0 || !phys_valid_[phys]) {
            // Unwritten / unmapped page: return zeros
            std::memset(dest_bytes + dest_offset, 0, static_cast<size_t>(to_copy));
            dest_offset += static_cast<size_t>(to_copy);
        } else {
            // Read 8-byte chunks, validate ECC and apply bit error simulation if degraded
            uint64_t chunk_start = (static_cast<uint64_t>(phys) * PAGE_SIZE + page_offset) & ~7ULL;
            uint64_t chunk_end = (static_cast<uint64_t>(phys) * PAGE_SIZE + page_offset + to_copy + 7) & ~7ULL;

            for (uint64_t chunk_offset = chunk_start; chunk_offset < chunk_end; chunk_offset += 8) {
                uint64_t local_offset = chunk_offset - static_cast<uint64_t>(phys) * PAGE_SIZE;
                uint64_t start_b = (local_offset < page_offset) ? page_offset : local_offset;
                uint64_t end_b = std::min<uint64_t>(local_offset + 8, page_offset + to_copy);

                uint64_t data_word = 0;
                std::memcpy(&data_word, memory_buffer_.get() + static_cast<size_t>(phys) * PAGE_SIZE + local_offset, 8);
                uint8_t stored_ecc = ecc_buffer_[(static_cast<size_t>(phys) * PAGE_SIZE + local_offset) / 8];

                uint32_t writes = page_writes_[phys].load(std::memory_order_relaxed);
                uint32_t disturbs = page_disturbs_[phys].load(std::memory_order_relaxed);
                
                // Bit error probability combining write wear, disturb, and temperature TER compression
                if (writes > WEAR_THRESHOLD || disturbs > physics_cfg_.half_select_disturb_threshold) {
                    double prob = static_cast<double>(writes > WEAR_THRESHOLD ? (writes - WEAR_THRESHOLD) : 0) / WEAR_THRESHOLD * 0.03;
                    prob += static_cast<double>(disturbs) / (physics_cfg_.half_select_disturb_threshold * 10.0);
                    
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

    // Compute physics-accurate write voltage and Merz's Law switching latency
    double v_eff = CalculateEffectiveVoltage(offset, true);
    double dynamic_latency_ns = CalculateMerzSwitchingLatency(v_eff, true);

    total_switching_latency_accum_ns_.fetch_add(static_cast<uint64_t>(dynamic_latency_ns), std::memory_order_relaxed);
    total_switching_ops_.fetch_add(1, std::memory_order_relaxed);

    // Inject simulated latency
    if (dynamic_latency_ns > latency_ns_) {
        LatencyInjector dynamic_injector(static_cast<uint64_t>(dynamic_latency_ns));
        dynamic_injector.Inject();
    } else {
        injector_.Inject();
    }

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

        // Apply half-select disturb to neighboring physical pages in the same crossbar sub-block
        if (physics_cfg_.enable_disturb_tracking && page_count_ > 1) {
            int32_t neighbor_page = (new_phys + 1) % static_cast<int32_t>(page_count_);
            page_disturbs_[neighbor_page].fetch_add(1, std::memory_order_relaxed);
            total_half_select_disturbs_.fetch_add(1, std::memory_order_relaxed);
        }

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
        size_t initial_free = free_physical_pages_hot_.size() + free_physical_pages_cold_.size();
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

        size_t current_free = free_physical_pages_hot_.size() + free_physical_pages_cold_.size();
        if (current_free <= initial_free) {
            // No progress made in this GC cycle, break to avoid infinite loop
            break;
        }

        if (current_free >= target_free) break;
    }
}

// ============================================================
// BurstCoalescer Implementation
// ============================================================

BurstCoalescer::BurstCoalescer()
    : depth_(DEPTH)
{
    staging_ = std::make_unique<CoalescePage[]>(depth_);
    for (size_t i = 0; i < depth_; ++i) {
        staging_[i].data.fill(0);
        staging_[i].bytes_committed = 0;
        staging_[i].dirty           = false;
        staging_[i].base_lba        = 0;
    }
}

bool BurstCoalescer::PushWrite(uint64_t lba_offset, const void* src, size_t size) noexcept {
    if (!src || size == 0 || size > PAGE_SZ) return false;

    std::lock_guard<std::mutex> lock(mtx_);

    // Determine which staging page this write maps to
    uint64_t page_idx  = (lba_offset / PAGE_SZ) % depth_;
    uint64_t page_off  = lba_offset % PAGE_SZ;

    // Clamp to page boundary
    size_t to_copy = std::min(size, static_cast<size_t>(PAGE_SZ - page_off));

    CoalescePage& pg = staging_[page_idx];
    if (!pg.dirty) {
        pg.base_lba = (lba_offset / PAGE_SZ) * PAGE_SZ;
        pg.dirty    = true;
        queue_depth_.fetch_add(1, std::memory_order_relaxed);
    }

    std::memcpy(pg.data.data() + page_off,
                static_cast<const uint8_t*>(src),
                to_copy);
    pg.bytes_committed += static_cast<uint32_t>(to_copy);
    if (pg.bytes_committed > PAGE_SZ)
        pg.bytes_committed = PAGE_SZ;  // clamp

    host_bytes_.fetch_add(to_copy, std::memory_order_relaxed);
    return true;
}

size_t BurstCoalescer::FlushToFTL(FTJController& ftl, size_t max_pages) noexcept {
    size_t flushed = 0;
    std::lock_guard<std::mutex> lock(mtx_);

    for (size_t i = 0; i < depth_ && flushed < max_pages; ++i) {
        CoalescePage& pg = staging_[i];
        if (!pg.dirty) continue;

        // Write the full coalesced page as a single sequential write
        bool ok = ftl.Write(pg.base_lba, pg.data.data(), PAGE_SZ);
        if (ok) {
            flash_bytes_.fetch_add(PAGE_SZ, std::memory_order_relaxed);
            pages_prog_.fetch_add(1, std::memory_order_relaxed);
        }

        // Reset staging page
        pg.data.fill(0);
        pg.bytes_committed = 0;
        pg.dirty           = false;
        pg.base_lba        = 0;
        queue_depth_.fetch_sub(1, std::memory_order_relaxed);
        ++flushed;
    }

    // Account for GC invocations (approximated by FTL physical write overhead)
    uint64_t host = host_bytes_.load(std::memory_order_relaxed);
    uint64_t flash = flash_bytes_.load(std::memory_order_relaxed);
    // GC is triggered when WAF > 1.5 — approximate as one GC per 8 flushes
    if (flushed > 0 && flash > 0 && host > 0) {
        double ratio = static_cast<double>(flash) / static_cast<double>(host);
        if (ratio > 1.5) {
            gc_calls_.fetch_add(1, std::memory_order_relaxed);
            blocks_erased_.fetch_add(1, std::memory_order_relaxed);
        }
    }

    return flushed;
}

double BurstCoalescer::GetWAF() const noexcept {
    uint64_t host  = host_bytes_.load(std::memory_order_relaxed);
    uint64_t flash = flash_bytes_.load(std::memory_order_relaxed);
    if (host == 0) return 1.0;
    return static_cast<double>(flash) / static_cast<double>(host);
}

size_t BurstCoalescer::GetPendingPages() const noexcept {
    std::lock_guard<std::mutex> lock(mtx_);
    size_t count = 0;
    for (size_t i = 0; i < depth_; ++i)
        if (staging_[i].dirty) ++count;
    return count;
}

size_t BurstCoalescer::GetQueueDepth() const noexcept {
    return static_cast<size_t>(queue_depth_.load(std::memory_order_relaxed));
}

NandMetrics BurstCoalescer::GetNandMetrics() const noexcept {
    NandMetrics m;
    m.gc_invocations    = gc_calls_.load(std::memory_order_relaxed);
    m.blocks_erased     = blocks_erased_.load(std::memory_order_relaxed);
    m.pages_programmed  = pages_prog_.load(std::memory_order_relaxed);
    m.waf               = GetWAF();
    m.max_pe_cycles     = 0;   // Populated by FTJController telemetry
    m.wear_uniformity   = 0.0; // Populated by FTJController telemetry
    m.active_queue_depth = GetQueueDepth();
    return m;
}

void BurstCoalescer::Reset() noexcept {
    std::lock_guard<std::mutex> lock(mtx_);
    for (size_t i = 0; i < depth_; ++i) {
        staging_[i].data.fill(0);
        staging_[i].bytes_committed = 0;
        staging_[i].dirty           = false;
        staging_[i].base_lba        = 0;
    }
    host_bytes_.store(0, std::memory_order_relaxed);
    flash_bytes_.store(0, std::memory_order_relaxed);
    gc_calls_.store(0, std::memory_order_relaxed);
    blocks_erased_.store(0, std::memory_order_relaxed);
    pages_prog_.store(0, std::memory_order_relaxed);
    queue_depth_.store(0, std::memory_order_relaxed);
}

} // namespace ftj


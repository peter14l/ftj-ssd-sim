#include "ftj_engine.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <intrin.h>
#include <algorithm>
#include <cstring>
#include <stdexcept>

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

// --- FTJController Implementation ---

FTJController::FTJController(size_t capacity_bytes, uint64_t latency_ns)
    : capacity_(capacity_bytes), latency_ns_(latency_ns), injector_(latency_ns) {
    
    // Allocate the virtual memory buffer
    memory_buffer_ = std::make_unique<uint8_t[]>(capacity_);
    // Zero-initialize backing buffer
    std::fill_n(memory_buffer_.get(), capacity_, uint8_t{0});
}

FTJController::~FTJController() = default;

bool FTJController::Read(uint64_t offset, void* dest, size_t size) const noexcept {
    if (!dest || size > capacity_ || offset > capacity_ - size) {
        return false;
    }

    // Inject exact simulated latency
    injector_.Inject();

    // Perform standard RAM copy
    std::memcpy(dest, memory_buffer_.get() + offset, size);
    total_reads_++;
    return true;
}

bool FTJController::Write(uint64_t offset, const void* src, size_t size) noexcept {
    if (!src || size > capacity_ || offset > capacity_ - size) {
        return false;
    }

    // Inject exact simulated latency
    injector_.Inject();

    // Perform standard RAM copy (simulating zero-wear, direct write)
    std::memcpy(memory_buffer_.get() + offset, src, size);
    total_writes_++;
    return true;
}

} // namespace ftj

#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>
#include <memory>
#include <string>
#include <atomic>
#include <mutex>
#include <algorithm>

#ifdef _MSC_VER
#pragma warning(disable: 4324)
#endif

namespace ftj {

// High-precision latency injector using CPU Time Stamp Counter (TSC)
class LatencyInjector {
public:
    explicit LatencyInjector(uint64_t latency_ns = 8);

    // Calibrates the TSC frequency against QueryPerformanceCounter
    static void Calibrate() noexcept;

    // Spin-waits until the configured latency has elapsed
    void Inject() const noexcept;

    // Returns the calibrated frequency in cycles per nanosecond
    static double GetCyclesPerNs() noexcept;

private:
    uint64_t latency_ns_;
    static inline double cycles_per_ns_ = 0.0;
    static inline bool calibrated_ = false;
};

// Core FTJ Controller modeling byte-addressable, zero-wear storage
class FTJController {
public:
    explicit FTJController(size_t capacity_bytes, uint64_t latency_ns = 8);
    ~FTJController();

    // Prevent copying/assignment
    FTJController(const FTJController&) = delete;
    FTJController& operator=(const FTJController&) = delete;
    FTJController(FTJController&&) noexcept = default;
    FTJController& operator=(FTJController&&) noexcept = default;

    // Byte-addressable read operation with exact latency injection and ECC validation
    bool Read(uint64_t offset, void* dest, size_t size) const noexcept;

    // Byte-addressable write operation with exact latency injection, wear updates, and ECC generation
    bool Write(uint64_t offset, const void* src, size_t size) noexcept;

    // Retrieve stats
    size_t GetCapacity() const noexcept { return capacity_; }
    uint64_t GetTotalReads() const noexcept { return total_reads_.load(std::memory_order_relaxed); }
    uint64_t GetTotalWrites() const noexcept { return total_writes_.load(std::memory_order_relaxed); }
    uint64_t GetLatencyNs() const noexcept { return latency_ns_; }

    // ECC & Wear Telemetry API
    uint64_t GetCorrectedErrors() const noexcept { return corrected_errors_.load(std::memory_order_relaxed); }
    uint64_t GetUncorrectableErrors() const noexcept { return uncorrectable_errors_.load(std::memory_order_relaxed); }
    uint64_t GetTotalBitFlips() const noexcept { return total_bit_flips_.load(std::memory_order_relaxed); }
    double GetMaxWearPercentage() const noexcept;
    void InjectHeavyWear(uint64_t offset, uint32_t write_count) noexcept;

    // Physical write accounting (bytes) — useful for WAF metrics
    uint64_t GetTotalPhysicalBytesWritten() const noexcept;

    // Static ECC Helpers
    static uint8_t CalculateECC(uint64_t data) noexcept;
    static int DecodeAndCorrect(uint64_t& data, uint8_t stored_ecc) noexcept;

    static constexpr uint32_t WEAR_THRESHOLD = 50000; // Simulated threshold before bit degradation

private:
    size_t capacity_;
    uint64_t latency_ns_;
    std::unique_ptr<uint8_t[]> memory_buffer_;
    std::unique_ptr<uint8_t[]> ecc_buffer_;          // Stores 1 byte of ECC per 8-byte chunk
    // Tracks write counts per 4KB page (atomic array allocated on heap to avoid vector move requirements)
    std::unique_ptr<std::atomic<uint32_t>[]> page_writes_;
    size_t page_count_ = 0;

    // Simple log-structured FTL simulation (page-granular)
    static constexpr size_t PAGE_SIZE = 4096;
    static constexpr size_t PAGES_PER_BLOCK = 256; // 1MB block
    size_t num_blocks_ = 0;

    // Logical-to-physical mapping (one entry per logical page)
    std::vector<int32_t> l2p_map_; // -1 = unmapped

    // Physical page metadata
    std::vector<char> phys_valid_; // 1 = valid/mapped, 0 = free/invalid
    std::vector<int32_t> phys_owner_lba_; // which logical page maps here, -1 if none
    std::vector<int32_t> phys_block_; // block id for each physical page
    std::vector<int32_t> block_valid_count_; // number of valid pages per block

    // Free lists of physical pages (hot/cold separation)
    std::vector<int32_t> free_physical_pages_hot_;
    std::vector<int32_t> free_physical_pages_cold_;

    // Simple mapping lock for simulation correctness (coarse-grained)
    mutable std::mutex mapping_mutex_;

    // LBA hot counters for hot/cold classification
    std::vector<uint32_t> lba_hot_counters_;
    static constexpr uint32_t HOT_THRESHOLD = 4; // writes to consider an LBA 'hot'

    // GC threshold: when free pages fall below this absolute count, trigger GC
    size_t gc_low_watermark_ = 0; // set at init
    size_t gc_target_free_ = 0;

    // Helper GC/allocation routines
    int32_t AllocatePhysicalPage(bool prefer_hot = false) noexcept;
    void RunGC(size_t target_free) noexcept;
    LatencyInjector injector_;

    // Performance & ECC counters
    mutable std::atomic<uint64_t> total_reads_{0};
    std::atomic<uint64_t> total_writes_{0};
    mutable std::atomic<uint64_t> corrected_errors_{0};
    mutable std::atomic<uint64_t> uncorrectable_errors_{0};
    mutable std::atomic<uint64_t> total_bit_flips_{0};

    // Physical write accounting (bytes)
    mutable std::atomic<uint64_t> total_physical_bytes_written_{0};
};

// --- NVMe Queue structures ---

struct SQEntry {
    uint8_t opcode; // 0 = Read, 1 = Write
    uint64_t offset;
    void* buffer;
    size_t size;
    uint32_t cid;
};

struct CQEntry {
    uint32_t cid;
    int32_t status;
};

// Multi-Producer Multi-Consumer (MPMC) lock-free circular ring buffer (Vyukov's queue)
template<typename T>
class LockFreeRingBuffer {
public:
    explicit LockFreeRingBuffer(size_t buffer_size)
        : size_(buffer_size), buffer_mask_(buffer_size - 1) {
        // Enforce size power of 2
        if ((buffer_size & (buffer_size - 1)) != 0) {
            // Find next power of 2
            size_ = 1;
            while (size_ < buffer_size) size_ <<= 1;
            buffer_mask_ = size_ - 1;
        }
        
        cells_ = std::make_unique<Cell[]>(size_);
        for (size_t i = 0; i < size_; ++i) {
            cells_[i].sequence.store(i, std::memory_order_relaxed);
        }
        enqueue_pos_.store(0, std::memory_order_relaxed);
        dequeue_pos_.store(0, std::memory_order_relaxed);
    }

    bool Push(const T& data) noexcept {
        Cell* cell;
        size_t pos = enqueue_pos_.load(std::memory_order_relaxed);
        for (;;) {
            cell = &cells_[pos & buffer_mask_];
            size_t seq = cell->sequence.load(std::memory_order_acquire);
            intptr_t dif = static_cast<intptr_t>(seq) - static_cast<intptr_t>(pos);
            if (dif == 0) {
                if (enqueue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                    break;
                }
            } else if (dif < 0) {
                return false; // Queue full
            } else {
                pos = enqueue_pos_.load(std::memory_order_relaxed);
            }
        }
        cell->data = data;
        cell->sequence.store(pos + 1, std::memory_order_release);
        return true;
    }

    bool Pop(T& data) noexcept {
        Cell* cell;
        size_t pos = dequeue_pos_.load(std::memory_order_relaxed);
        for (;;) {
            cell = &cells_[pos & buffer_mask_];
            size_t seq = cell->sequence.load(std::memory_order_acquire);
            intptr_t dif = static_cast<intptr_t>(seq) - static_cast<intptr_t>(pos + 1);
            if (dif == 0) {
                if (dequeue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                    break;
                }
            } else if (dif < 0) {
                return false; // Queue empty
            } else {
                pos = dequeue_pos_.load(std::memory_order_relaxed);
            }
        }
        data = cell->data;
        cell->sequence.store(pos + size_, std::memory_order_release);
        return true;
    }

private:
    struct alignas(64) Cell {
        std::atomic<size_t> sequence;
        T data;
    };

    size_t size_;
    size_t buffer_mask_;
    std::unique_ptr<Cell[]> cells_;
    alignas(64) std::atomic<size_t> enqueue_pos_;
    alignas(64) std::atomic<size_t> dequeue_pos_;
};

// Represents a pair of Submission and Completion Queues
class NVMeQueuePair {
public:
    explicit NVMeQueuePair(size_t queue_depth)
        : sq_(queue_depth), cq_(queue_depth) {}

    bool Submit(const SQEntry& entry) noexcept { return sq_.Push(entry); }
    bool Reap(CQEntry& entry) noexcept { return cq_.Pop(entry); }

    bool PopRequest(SQEntry& entry) noexcept { return sq_.Pop(entry); }
    bool CompleteRequest(const CQEntry& entry) noexcept { return cq_.Push(entry); }

private:
    LockFreeRingBuffer<SQEntry> sq_;
    LockFreeRingBuffer<CQEntry> cq_;
};

} // namespace ftj

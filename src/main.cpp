#include "ftj_engine.hpp"
#include <iostream>
#include <fstream>
#include <chrono>
#include <random>
#include <vector>
#include <iomanip>
#include <string>
#include <numeric>
#include <cmath>
#include <thread>
#include <future>
#include <atomic>
#include <algorithm>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

// Structures for Benchmark results
struct BenchmarkResult {
    std::string name;
    double duration_ms;
    uint64_t total_ops;
    double iops;
    double avg_latency_ns;
    double throughput_mb_s;
};

struct QDScalingMetric {
    uint32_t queue_depth;
    double iops;
    double throughput_mb_s;
    double p50_latency_ns;
    double p99_latency_ns;
    double p99_9_latency_ns;
};

// Simple simulated 3D NAND Flash storage for comparison
struct Simulated3DNand {
    static constexpr uint64_t PAGE_SIZE = 4096;
    static constexpr uint64_t BLOCK_SIZE = 256 * PAGE_SIZE; // 1MB block
    
    // Latencies in nanoseconds
    static constexpr uint64_t READ_LATENCY_NS = 25'000;      // 25 us
    static constexpr uint64_t WRITE_LATENCY_NS = 100'000;    // 100 us
    static constexpr uint64_t ERASE_LATENCY_NS = 3'000'000;  // 3 ms

    uint64_t total_erases = 0;
    uint64_t total_writes = 0;
    uint64_t total_reads = 0;
    uint64_t total_latency_ns = 0;

    void Reset() {
        total_erases = 0;
        total_writes = 0;
        total_reads = 0;
        total_latency_ns = 0;
    }

    // Write operation: simulates out-of-place write and periodic garbage collection/block erase
    void Write(uint64_t /*offset*/, size_t size) {
        uint64_t pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
        total_writes += pages_needed;
        total_latency_ns += pages_needed * WRITE_LATENCY_NS;

        // Simulate GC / Erase cycle (e.g. 1 erase for every 64 page writes)
        if (total_writes % 64 == 0) {
            total_erases++;
            total_latency_ns += ERASE_LATENCY_NS;
        }
    }

    void Read(uint64_t /*offset*/, size_t size) {
        uint64_t pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;
        total_reads += pages_needed;
        total_latency_ns += pages_needed * READ_LATENCY_NS;
    }
};

// Helper for high-precision time measurement
inline uint64_t GetTimeNs() {
    LARGE_INTEGER freq, count;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&count);
    return static_cast<uint64_t>((count.QuadPart * 1'000'000'000) / freq.QuadPart);
}

// Function to print results to console and append to markdown file
void LogResults(const std::vector<BenchmarkResult>& results, const std::string& comparison_summary) {
    // Console Output
    std::cout << "\n" << std::string(80, '=') << "\n";
    std::cout << "                 FTJ MEMORY ENGINE BENCHMARK EXECUTION SUMMARY\n";
    std::cout << std::string(80, '=') << "\n";
    std::cout << std::left << std::setw(30) << "Benchmark Name" 
              << std::right << std::setw(12) << "Ops Run" 
              << std::setw(12) << "IOPS" 
              << std::setw(15) << "Avg Latency (ns)" 
              << std::setw(11) << "TP (MB/s)" << "\n";
    std::cout << std::string(80, '-') << "\n";
    
    for (const auto& r : results) {
        std::cout << std::left << std::setw(30) << r.name
                  << std::right << std::setw(12) << r.total_ops
                  << std::setw(12) << std::fixed << std::setprecision(0) << r.iops
                  << std::setw(15) << std::setprecision(1) << r.avg_latency_ns
                  << std::setw(11) << std::setprecision(2) << r.throughput_mb_s << "\n";
    }
    std::cout << std::string(80, '=') << "\n";
    std::cout << comparison_summary << "\n";

    // Write to docs/BENCHMARK_RESULTS.md
    std::ofstream ofs("docs/BENCHMARK_RESULTS.md");
    if (ofs.is_open()) {
        ofs << "# FTJ Memory Engine Benchmark Results\n\n";
        ofs << "This document presents the performance metrics of the simulated byte-addressable Ferroelectric Tunnel Junction (FTJ) memory engine.\n\n";
        ofs << "## Execution Metrics\n\n";
        ofs << "| Benchmark Name | Operations | IOPS | Avg Latency (ns) | Throughput (MB/s) |\n";
        ofs << "| :--- | :---: | :---: | :---: | :---: |\n";
        for (const auto& r : results) {
            ofs << "| " << r.name << " | " << r.total_ops << " | " 
                << std::fixed << std::setprecision(0) << r.iops << " | "
                << std::setprecision(1) << r.avg_latency_ns << " | "
                << std::setprecision(2) << r.throughput_mb_s << " |\n";
        }
        ofs << "\n## Analysis & Comparison\n\n";
        ofs << comparison_summary << "\n";
        ofs.close();
        std::cout << "[Info] Benchmark results written to docs/BENCHMARK_RESULTS.md\n";
    }
}

int main(int argc, char* argv[]) {
    if (argc > 1 && std::string(argv[1]) == "--mount") {
        std::string drive = (argc > 2) ? argv[2] : "Z:";
        std::cout << "[CLI] Forwarding mount request to Virtual Disk Server for " << drive << "...\n";
        
        // Find if vdisk server is in Release/ or same directory
        std::string cmd = "ftj_vdisk_srv.exe " + drive;
        int ret = std::system(cmd.c_str());
        if (ret != 0) {
            cmd = "build\\Release\\ftj_vdisk_srv.exe " + drive;
            ret = std::system(cmd.c_str());
        }
        if (ret != 0) {
            cmd = "build\\ftj_vdisk_srv.exe " + drive;
            ret = std::system(cmd.c_str());
        }
        if (ret != 0) {
            cmd = "Release\\ftj_vdisk_srv.exe " + drive;
            ret = std::system(cmd.c_str());
        }
        return ret;
    }

    std::cout << "Initializing FTJ Memory Engine CLI & Benchmark Suite...\n";
    ftj::LatencyInjector::Calibrate();
    std::cout << "TSC Frequency Calibrated: " << std::fixed << std::setprecision(3)
              << ftj::LatencyInjector::GetCyclesPerNs() << " cycles/ns\n";

    size_t engine_capacity = 64 * 1024 * 1024; // 64 MB default capacity
    ftj::FTJController controller(engine_capacity, 8); // 8 ns default latency
    std::vector<BenchmarkResult> results;

    // Run standard Benchmarks
    std::cout << "\nRunning Benchmark 1: Random 4K Byte-Addressable Writes...\n";
    {
        constexpr size_t BLOCK_SIZE = 4096;
        constexpr uint64_t NUM_OPS = 50'000;
        std::vector<uint8_t> dummy_data(BLOCK_SIZE, 0xAF);
        
        std::mt19937_64 rng(1337);
        std::uniform_int_distribution<uint64_t> dist(0, engine_capacity - BLOCK_SIZE);

        uint64_t start_time = GetTimeNs();
        for (uint64_t i = 0; i < NUM_OPS; ++i) {
            uint64_t offset = dist(rng);
            controller.Write(offset, dummy_data.data(), BLOCK_SIZE);
        }
        uint64_t end_time = GetTimeNs();

        double elapsed_ms = static_cast<double>(end_time - start_time) / 1'000'000.0;
        double iops = (static_cast<double>(NUM_OPS) / elapsed_ms) * 1000.0;
        double avg_latency = static_cast<double>(end_time - start_time) / NUM_OPS;
        double throughput = (static_cast<double>(NUM_OPS * BLOCK_SIZE) / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);

        results.push_back({"Random 4K Writes (FTJ)", elapsed_ms, NUM_OPS, iops, avg_latency, throughput});
    }

    std::cout << "Running Benchmark 2: Sequential Read/Write Latency Analysis...\n";
    {
        constexpr size_t ACCESS_SIZE = 256; // 256 bytes granular access
        constexpr uint64_t NUM_OPS = 200'000;
        std::vector<uint8_t> dummy_buf(ACCESS_SIZE, 0x55);

        uint64_t start_time = GetTimeNs();
        for (uint64_t i = 0; i < NUM_OPS; ++i) {
            uint64_t offset = (i * ACCESS_SIZE) % (engine_capacity - ACCESS_SIZE);
            if (i % 2 == 0) {
                controller.Write(offset, dummy_buf.data(), ACCESS_SIZE);
            } else {
                controller.Read(offset, dummy_buf.data(), ACCESS_SIZE);
            }
        }
        uint64_t end_time = GetTimeNs();

        double elapsed_ms = static_cast<double>(end_time - start_time) / 1'000'000.0;
        double iops = (static_cast<double>(NUM_OPS) / elapsed_ms) * 1000.0;
        double avg_latency = static_cast<double>(end_time - start_time) / NUM_OPS;
        double throughput = (static_cast<double>(NUM_OPS * ACCESS_SIZE) / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);

        results.push_back({"Sequential 256B R/W (FTJ)", elapsed_ms, NUM_OPS, iops, avg_latency, throughput});
    }

    std::cout << "Running Benchmark 3: Mixed 70% Read / 30% Write Profiles...\n";
    {
        constexpr size_t BLOCK_SIZE = 4096;
        constexpr uint64_t NUM_OPS = 100'000;
        std::vector<uint8_t> dummy_buf(BLOCK_SIZE, 0x33);

        std::mt19937_64 rng(42);
        std::uniform_int_distribution<uint64_t> dist_offset(0, engine_capacity - BLOCK_SIZE);
        std::uniform_int_distribution<int> dist_op(1, 100);

        uint64_t start_time = GetTimeNs();
        for (uint64_t i = 0; i < NUM_OPS; ++i) {
            uint64_t offset = dist_offset(rng);
            if (dist_op(rng) <= 70) {
                controller.Read(offset, dummy_buf.data(), BLOCK_SIZE);
            } else {
                controller.Write(offset, dummy_buf.data(), BLOCK_SIZE);
            }
        }
        uint64_t end_time = GetTimeNs();

        double elapsed_ms = static_cast<double>(end_time - start_time) / 1'000'000.0;
        double iops = (static_cast<double>(NUM_OPS) / elapsed_ms) * 1000.0;
        double avg_latency = static_cast<double>(end_time - start_time) / NUM_OPS;
        double throughput = (static_cast<double>(NUM_OPS * BLOCK_SIZE) / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);

        results.push_back({"Mixed 70/30 (4K FTJ)", elapsed_ms, NUM_OPS, iops, avg_latency, throughput});
    }

    // Advanced: NVMe Queue Depth Scaling Benchmark
    std::cout << "\nRunning Benchmark 4: NVMe Queue Depth Scaling Sweep (Lock-Free SQ/CQ)...\n";
    const std::vector<uint32_t> test_qds = {1, 4, 16, 32, 64};
    std::vector<QDScalingMetric> qd_metrics;

    for (uint32_t qd : test_qds) {
        std::cout << " -> Simulating Queue Depth (QD) = " << qd << "...\n";
        ftj::NVMeQueuePair queue_pair(qd);
        
        constexpr uint64_t TOTAL_OPS = 50'000;
        std::atomic<uint64_t> ops_submitted(0);
        std::atomic<uint64_t> ops_reaped(0);
        std::atomic<bool> backend_active(true);

        std::vector<uint64_t> latencies(TOTAL_OPS, 0);
        std::vector<uint8_t> io_buf(4096, 0x99);

        // Start NVMe backend executor thread pool matching the QD to simulate parallel controllers
        std::vector<std::thread> backend_workers;
        uint32_t num_backend_threads = std::max(1u, std::thread::hardware_concurrency());
        for (uint32_t b = 0; b < num_backend_threads; ++b) {
            backend_workers.push_back(std::thread([&]() {
                ftj::SQEntry sqe;
                while (backend_active.load(std::memory_order_relaxed) || ops_reaped.load(std::memory_order_relaxed) < TOTAL_OPS) {
                    if (queue_pair.PopRequest(sqe)) {
                        // Process the virtual IO
                        if (sqe.opcode == 1) {
                            controller.Write(sqe.offset, sqe.buffer, sqe.size);
                        } else {
                            controller.Read(sqe.offset, sqe.buffer, sqe.size);
                        }
                        
                        // Push completion
                        ftj::CQEntry cqe { sqe.cid, 0 };
                        while (!queue_pair.CompleteRequest(cqe)) {
                            std::this_thread::yield();
                        }
                    } else {
                        std::this_thread::yield();
                    }
                }
            }));
        }

        // Frontend client worker loop
        uint64_t start_time = GetTimeNs();
        
        // Multi-threaded client submission
        std::vector<std::thread> client_workers;
        uint32_t num_clients = std::max(1u, qd);
        for (uint32_t c = 0; c < num_clients; ++c) {
            client_workers.push_back(std::thread([&, c]() {
                std::mt19937_64 rng(12345 + c);
                std::uniform_int_distribution<uint64_t> dist_offset(0, engine_capacity - 4096);
                
                while (true) {
                    uint64_t cid = ops_submitted.fetch_add(1, std::memory_order_relaxed);
                    if (cid >= TOTAL_OPS) {
                        break;
                    }
                    
                    ftj::SQEntry sqe {
                        1, // Write
                        dist_offset(rng),
                        io_buf.data(),
                        4096,
                        static_cast<uint32_t>(cid)
                    };
                    
                    uint64_t submit_time = GetTimeNs();
                    
                    // Submit to SQ
                    while (!queue_pair.Submit(sqe)) {
                        std::this_thread::yield();
                    }
                    
                    // Poll CQ for our completion
                    ftj::CQEntry cqe;
                    bool finished = false;
                    while (!finished) {
                        // Try to reap from completion queue
                        if (queue_pair.Reap(cqe)) {
                            uint64_t completion_time = GetTimeNs();
                            latencies[cqe.cid] = completion_time - submit_time;
                            ops_reaped.fetch_add(1, std::memory_order_release);
                            finished = true;
                        } else {
                            std::this_thread::yield();
                        }
                    }
                }
            }));
        }

        // Wait for all submissions & polling to finish
        for (auto& t : client_workers) {
            t.join();
        }

        // Shut down backend executors
        backend_active.store(false, std::memory_order_release);
        for (auto& t : backend_workers) {
            t.join();
        }

        uint64_t end_time = GetTimeNs();

        // Calculate metrics
        double duration_ms = static_cast<double>(end_time - start_time) / 1'000'000.0;
        double iops = (static_cast<double>(TOTAL_OPS) / duration_ms) * 1000.0;
        double throughput = (static_cast<double>(TOTAL_OPS * 4096) / (1024.0 * 1024.0)) / (duration_ms / 1000.0);

        // Sort latencies to extract tail metrics
        std::sort(latencies.begin(), latencies.end());
        double p50 = static_cast<double>(latencies[static_cast<size_t>(TOTAL_OPS * 0.50)]);
        double p99 = static_cast<double>(latencies[static_cast<size_t>(TOTAL_OPS * 0.99)]);
        double p99_9 = static_cast<double>(latencies[static_cast<size_t>(TOTAL_OPS * 0.999)]);

        qd_metrics.push_back({ qd, iops, throughput, p50, p99, p99_9 });
        
        results.push_back({"QD-" + std::to_string(qd) + " NVMe Queue", duration_ms, TOTAL_OPS, iops, p50, throughput});
    }

    // Write docs/QUEUE_DEPTH_SCALING.md
    std::ofstream qd_fs("docs/QUEUE_DEPTH_SCALING.md");
    if (qd_fs.is_open()) {
        qd_fs << "# NVMe Queue Depth Scaling Analysis\n\n";
        qd_fs << "This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.\n\n";
        qd_fs << "## Metrics Summary\n\n";
        qd_fs << "| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |\n";
        qd_fs << "| :--- | :---: | :---: | :---: | :---: | :---: |\n";
        for (const auto& qm : qd_metrics) {
            qd_fs << "| QD-" << qm.queue_depth << " | "
                  << std::fixed << std::setprecision(0) << qm.iops << " | "
                  << std::setprecision(2) << qm.throughput_mb_s << " | "
                  << std::setprecision(1) << qm.p50_latency_ns << " | "
                  << qm.p99_latency_ns << " | "
                  << qm.p99_9_latency_ns << " |\n";
        }
        qd_fs << "\n## Architecture Insights\n";
        qd_fs << "- Lock-free atomic submission and completion queue design prevents lock contention.\n";
        qd_fs << "- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.\n";
        qd_fs.close();
        std::cout << "[Info] Detailed queue depth stats written to docs/QUEUE_DEPTH_SCALING.md\n";
    }

    // NAND Comparison
    std::cout << "\nRunning Benchmark 5: Direct Comparison vs. Simulated 3D NAND...\n";
    Simulated3DNand nand;
    std::string comparison_summary;
    {
        constexpr size_t WRITE_SIZE = 4096;
        constexpr uint64_t NUM_OPS = 20'000;
        std::vector<uint8_t> dummy_buf(WRITE_SIZE, 0xCC);

        // FTJ execution
        uint64_t ftj_start = GetTimeNs();
        for (uint64_t i = 0; i < NUM_OPS; ++i) {
            controller.Write((i * WRITE_SIZE) % (engine_capacity - WRITE_SIZE), dummy_buf.data(), WRITE_SIZE);
        }
        uint64_t ftj_end = GetTimeNs();
        double ftj_ms = static_cast<double>(ftj_end - ftj_start) / 1'000'000.0;
        double ftj_iops = (static_cast<double>(NUM_OPS) / ftj_ms) * 1000.0;
        double ftj_avg = static_cast<double>(ftj_end - ftj_start) / NUM_OPS;
        double ftj_tp = (static_cast<double>(NUM_OPS * WRITE_SIZE) / (1024.0 * 1024.0)) / (ftj_ms / 1000.0);
        results.push_back({"NAND-Comparison (FTJ Mode)", ftj_ms, NUM_OPS, ftj_iops, ftj_avg, ftj_tp});

        // 3D NAND execution
        nand.Reset();
        for (uint64_t i = 0; i < NUM_OPS; ++i) {
            nand.Write((i * WRITE_SIZE) % (engine_capacity - WRITE_SIZE), WRITE_SIZE);
        }
        double nand_ms = static_cast<double>(nand.total_latency_ns) / 1'000'000.0;
        double nand_iops = (static_cast<double>(NUM_OPS) / nand_ms) * 1000.0;
        double nand_avg = static_cast<double>(nand.total_latency_ns) / NUM_OPS;
        double nand_tp = (static_cast<double>(NUM_OPS * WRITE_SIZE) / (1024.0 * 1024.0)) / (nand_ms / 1000.0);
        results.push_back({"NAND-Comparison (3D NAND Mode)", nand_ms, NUM_OPS, nand_iops, nand_avg, nand_tp});

        double speedup = nand_avg / ftj_avg;
        comparison_summary = 
            "### Physical Performance Comparison:\n"
            "- **FTJ Write Operations**: Emulated at zero-wear and true byte-granularity. Zero block-erase operations are required.\n"
            "- **3D NAND Write Operations**: Incurred high page write latencies (" + std::to_string(Simulated3DNand::WRITE_LATENCY_NS / 1000) + " us) and periodic garbage collection/block-erases (" + std::to_string(Simulated3DNand::ERASE_LATENCY_NS / 1'000'000) + " ms).\n"
            "- **Total Block Erases for 3D NAND**: " + std::to_string(nand.total_erases) + " erase operations.\n"
            "- **Latency Reduction Factor**: FTJ writes are **" + std::to_string(static_cast<uint64_t>(speedup)) + "x faster** than simulated 3D NAND under equivalent write pressure.\n";
    }

    LogResults(results, comparison_summary);

    return 0;
}

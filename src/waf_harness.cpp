#include "ftj_engine.hpp"
#include <iostream>
#include <vector>
#include <random>
#include <chrono>

using namespace ftj;

int main(int argc, char** argv) {
    size_t capacity = 64 * 1024 * 1024; // 64 MiB
    size_t block = 4096;
    uint64_t ops = 10000;
    bool random_access = true;
    int read_percentage = 0; // 0 = all writes

    if (argc > 1) ops = std::stoull(argv[1]);
    if (argc > 2) block = std::stoul(argv[2]);
    if (argc > 3) read_percentage = std::stoi(argv[3]);
    if (argc > 4) random_access = std::stoi(argv[4]) != 0;

    FTJController ctrl(capacity, 8);

    std::mt19937_64 rng(42);
    std::uniform_int_distribution<uint64_t> dist(0, capacity - block);
    std::uniform_int_distribution<int> opdist(1,100);
    std::vector<uint8_t> write_buf(block, 0x5A);
    std::vector<uint8_t> read_buf(block);

    uint64_t logical_bytes_written = 0;
    uint64_t logical_bytes_read = 0;

    auto start = std::chrono::steady_clock::now();
    for (uint64_t i = 0; i < ops; ++i) {
        uint64_t off = random_access ? dist(rng) : ((i * block) % (capacity - block));
        bool do_read = (opdist(rng) <= read_percentage);
        if (do_read) {
            bool ok = ctrl.Read(off, read_buf.data(), block);
            if (!ok) {
                std::cerr << "Read failed at op " << i << "\n";
                return 3;
            }
            logical_bytes_read += block;
        } else {
            bool ok = ctrl.Write(off, write_buf.data(), block);
            if (!ok) {
                std::cerr << "Write failed at op " << i << "\n";
                return 2;
            }
            logical_bytes_written += block;
        }
    }
    auto end = std::chrono::steady_clock::now();
    double elapsed_s = std::chrono::duration<double>(end - start).count();

    uint64_t physical = ctrl.GetTotalPhysicalBytesWritten();
    uint64_t total_logical = logical_bytes_written + logical_bytes_read;
    std::cout << "OPS=" << ops << ", BLOCK=" << block << ", READ%=" << read_percentage << ", RANDOM=" << random_access << "\n";
    std::cout << "LOGICAL_WRITTEN_BYTES=" << logical_bytes_written << "\n";
    std::cout << "LOGICAL_READ_BYTES=" << logical_bytes_read << "\n";
    std::cout << "PHYSICAL_BYTES=" << physical << "\n";
    double waf = (physical > 0 && logical_bytes_written > 0) ? static_cast<double>(physical) / static_cast<double>(logical_bytes_written) : 0.0;
    std::cout << "WAF=" << waf << "\n";
    std::cout << "Throughput (MB/s): " << (static_cast<double>(total_logical) / (1024.0*1024.0)) / elapsed_s << "\n";

    return 0;
}

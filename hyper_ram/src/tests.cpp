// Copyright (c) 2026 HyperRAM Project. All Rights Reserved.
// Open-Hardware / Low-Cost Memory Architecture Initiative.
#include "bdi_engine.hpp"
#include "line_table.hpp"
#include "hyper_ram_controller.hpp"
#include <iostream>
#include <vector>
#include <random>
#include <cstring>
#include <cassert>

using namespace hyper_ram;

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cerr << "[-] FAILED: " << msg << " (" << __FILE__ << ":" << __LINE__ << ")\n"; \
            g_tests_failed++; \
            return false; \
        } \
    } while (0)

#define RUN_TEST(fn) \
    do { \
        std::cout << "[*] Running " << #fn << "...\n"; \
        if (fn()) { \
            std::cout << "[+] PASSED: " << #fn << "\n"; \
            g_tests_passed++; \
        } else { \
            std::cout << "[-] FAILED: " << #fn << "\n"; \
        } \
    } while (0)

bool TestZerosLossless() {
    alignas(64) std::array<uint8_t, 64> src{};
    CompressedLine comp = BDIEngine::Compress(src.data());
    TEST_ASSERT(comp.pattern == BDIPattern::ZEROS, "Pattern must be ZEROS");
    TEST_ASSERT(comp.compressed_size == 1, "Zeros size must be 1 byte tag");

    alignas(64) std::array<uint8_t, 64> dest{};
    dest.fill(0xAA);
    bool ok = BDIEngine::Decompress(comp, dest.data());
    TEST_ASSERT(ok, "Decompression failed");
    TEST_ASSERT(std::memcmp(src.data(), dest.data(), 64) == 0, "Data mismatch on zeros");
    return true;
}

bool TestRepeatedWordLossless() {
    alignas(64) std::array<uint64_t, 8> src{};
    src.fill(0xDEADBEEFCAFEBABEULL);

    CompressedLine comp = BDIEngine::Compress(src.data());
    TEST_ASSERT(comp.pattern == BDIPattern::REP_WORD, "Pattern must be REP_WORD");
    TEST_ASSERT(comp.compressed_size == 9, "Repeated word size must be 9 bytes");

    alignas(64) std::array<uint64_t, 8> dest{};
    bool ok = BDIEngine::Decompress(comp, dest.data());
    TEST_ASSERT(ok, "Decompression failed");
    TEST_ASSERT(std::memcmp(src.data(), dest.data(), 64) == 0, "Data mismatch on repeated word");
    return true;
}

bool TestBase8Delta1Lossless() {
    // Array of 64-bit pointers with small variations (e.g. heap pointers: 0x7FFF0000 + i*8)
    alignas(64) std::array<int64_t, 8> src{};
    int64_t base = 0x7FFF'0000'1000LL;
    for (size_t i = 0; i < 8; ++i) {
        src[i] = base + static_cast<int64_t>(i * 12);
    }

    CompressedLine comp = BDIEngine::Compress(src.data());
    TEST_ASSERT(comp.pattern == BDIPattern::BASE8_DELTA1, "Pattern must be BASE8_DELTA1");
    TEST_ASSERT(comp.compressed_size == 16, "Base8-Delta1 size must be 16 bytes");

    alignas(64) std::array<int64_t, 8> dest{};
    bool ok = BDIEngine::Decompress(comp, dest.data());
    TEST_ASSERT(ok, "Decompression failed");
    TEST_ASSERT(std::memcmp(src.data(), dest.data(), 64) == 0, "Data mismatch on Base8-Delta1");
    return true;
}

bool TestBase4Delta1Lossless() {
    // Array of 32-bit integers with small deltas
    alignas(64) std::array<int32_t, 16> src{};
    int32_t base = 500000;
    for (size_t i = 0; i < 16; ++i) {
        src[i] = base + static_cast<int32_t>(i * 3 - 20);
    }

    CompressedLine comp = BDIEngine::Compress(src.data());
    TEST_ASSERT(comp.pattern == BDIPattern::BASE4_DELTA1, "Pattern must be BASE4_DELTA1");
    TEST_ASSERT(comp.compressed_size == 20, "Base4-Delta1 size must be 20 bytes");

    alignas(64) std::array<int32_t, 16> dest{};
    bool ok = BDIEngine::Decompress(comp, dest.data());
    TEST_ASSERT(ok, "Decompression failed");
    TEST_ASSERT(std::memcmp(src.data(), dest.data(), 64) == 0, "Data mismatch on Base4-Delta1");
    return true;
}

bool TestIncompressibleFallback() {
    // High-entropy random data
    alignas(64) std::array<uint8_t, 64> src{};
    std::mt19937 rng(1337);
    for (auto& b : src) b = static_cast<uint8_t>(rng() & 0xFF);

    CompressedLine comp = BDIEngine::Compress(src.data());
    TEST_ASSERT(comp.pattern == BDIPattern::UNCOMPRESSED, "Must tag random noise as UNCOMPRESSED");
    TEST_ASSERT(comp.compressed_size == 64, "Uncompressed size must be 64");

    alignas(64) std::array<uint8_t, 64> dest{};
    bool ok = BDIEngine::Decompress(comp, dest.data());
    TEST_ASSERT(ok, "Decompression failed");
    TEST_ASSERT(std::memcmp(src.data(), dest.data(), 64) == 0, "Data mismatch on uncompressed fallback");
    return true;
}

bool TestLineTableAllocationAndCompaction() {
    // Virtual 1MB, Physical 512KB
    size_t virt = 1024 * 1024;
    size_t phys = 512 * 1024;
    MemoryLineTable table(virt, phys);

    alignas(64) std::array<uint64_t, 8> line{};
    for (size_t l = 0; l < 1000; ++l) {
        line.fill(0x1000 + l); // Repeated word (compresses to 9 bytes, slots to 16 bytes)
        CompressedLine comp = BDIEngine::Compress(line.data());
        bool stored = table.StoreLine(l, comp);
        TEST_ASSERT(stored, "Failed to store line in MemoryLineTable");
    }

    // Verify all lines read back correctly
    for (size_t l = 0; l < 1000; ++l) {
        alignas(64) std::array<uint64_t, 8> readback{};
        bool loaded = table.LoadLine(l, readback.data());
        TEST_ASSERT(loaded, "Failed to load line from MemoryLineTable");
        for (size_t i = 0; i < 8; ++i) {
            TEST_ASSERT(readback[i] == 0x1000 + l, "Line data mismatch");
        }
    }

    double ratio = table.GetCurrentCompressionRatio();
    TEST_ASSERT(ratio >= 3.5, "Compression ratio should be >= 3.5x for repeated words");
    return true;
}

bool TestHyperRAMControllerByteAddressable() {
    ControllerConfig cfg;
    cfg.virtual_capacity_bytes = 4 * 1024 * 1024; // 4MB
    cfg.physical_dram_bytes = 2 * 1024 * 1024;    // 2MB (2:1 physical ratio)
    HyperRAMController ctrl(cfg);

    // Write a string spanning across multiple cache lines with unaligned offsets
    const char* message = "HyperRAM: Ultra-low-latency hardware-compressed memory controller!";
    size_t len = std::strlen(message) + 1;
    uint64_t offset = 123; // Unaligned

    bool written = ctrl.Write(offset, message, len);
    TEST_ASSERT(written, "Unaligned write failed");

    std::vector<char> buffer(len, 0);
    bool read = ctrl.Read(offset, buffer.data(), len);
    TEST_ASSERT(read, "Unaligned read failed");
    TEST_ASSERT(std::strcmp(message, buffer.data()) == 0, "Readback string does not match written string");

    return true;
}

bool TestVirtualCapacityDoublerStress() {
    // 8MB virtual memory packed into 4MB physical memory
    ControllerConfig cfg;
    cfg.virtual_capacity_bytes = 8 * 1024 * 1024;
    cfg.physical_dram_bytes = 4 * 1024 * 1024;
    HyperRAMController ctrl(cfg);

    // Populate 6MB of virtual memory (exceeding 4MB physical capacity!)
    std::vector<int64_t> test_data(1024 * 1024); // 8MB of pointers
    for (size_t i = 0; i < test_data.size(); ++i) {
        test_data[i] = 0x7FFF0000 + (i % 8); // Compresses efficiently
    }

    size_t write_bytes = 6 * 1024 * 1024; // 6MB
    bool ok = ctrl.Write(0, test_data.data(), write_bytes);
    TEST_ASSERT(ok, "Failed to write 6MB into 4MB physical pool with compression!");

    MemoryTelemetry tel = ctrl.GetTelemetry();
    TEST_ASSERT(tel.compression_ratio > 1.5, "Compression ratio should be > 1.5x");
    TEST_ASSERT(tel.physical_bytes_stored <= cfg.physical_dram_bytes, "Physical storage must not exceed capacity");

    // Read back and verify
    std::vector<int64_t> read_data(write_bytes / sizeof(int64_t));
    ok = ctrl.Read(0, read_data.data(), write_bytes);
    TEST_ASSERT(ok, "Failed to read back 6MB");
    TEST_ASSERT(std::memcmp(test_data.data(), read_data.data(), write_bytes) == 0, "6MB stress data mismatch");

    return true;
}

int main() {
    std::cout << "========================================================\n";
    std::cout << "  HyperRAM Verification & Unit Test Suite (Lossless Core) \n";
    std::cout << "========================================================\n";

    RUN_TEST(TestZerosLossless);
    RUN_TEST(TestRepeatedWordLossless);
    RUN_TEST(TestBase8Delta1Lossless);
    RUN_TEST(TestBase4Delta1Lossless);
    RUN_TEST(TestIncompressibleFallback);
    RUN_TEST(TestLineTableAllocationAndCompaction);
    RUN_TEST(TestHyperRAMControllerByteAddressable);
    RUN_TEST(TestVirtualCapacityDoublerStress);

    std::cout << "========================================================\n";
    std::cout << "  Summary: " << g_tests_passed << " Passed, " << g_tests_failed << " Failed\n";
    std::cout << "========================================================\n";

    return (g_tests_failed == 0) ? 0 : 1;
}

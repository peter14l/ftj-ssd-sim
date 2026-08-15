#include "ftj_engine.hpp"
#include <cassert>
#include <iostream>
#include <thread>
#include <vector>

using namespace ftj;

void TestECC() {
    uint64_t data = 0x0123456789ABCDEFULL;
    uint8_t ecc = FTJController::CalculateECC(data);
    uint64_t copy = data;
    int res = FTJController::DecodeAndCorrect(copy, ecc);
    assert(res == 0);

    // flip one bit -> should be corrected
    uint64_t flipped = data ^ (1ULL << 5);
    res = FTJController::DecodeAndCorrect(flipped, ecc);
    assert(res == 1);

    // flip two bits -> uncorrectable (most likely)
    uint64_t dbl = data ^ (1ULL << 5) ^ (1ULL << 10);
    res = FTJController::DecodeAndCorrect(dbl, ecc);
    assert(res == 2);
}

void TestRingBufferAndQueue() {
    NVMeQueuePair qp(8);
    // producer thread
    std::thread p([&]() {
        for (uint32_t i = 0; i < 100; ++i) {
            SQEntry e{1, i * 8, nullptr, 8, i};
            while (!qp.Submit(e)) std::this_thread::yield();
        }
    });

    // consumer thread
    std::thread c([&]() {
        uint32_t seen = 0;
        while (seen < 100) {
            CQEntry rx;
            if (qp.Reap(rx)) {
                ++seen;
            } else {
                std::this_thread::yield();
            }
        }
    });

    p.join();
    c.join();
}

void TestControllerConcurrentRW() {
    FTJController ctrl(1024 * 1024, 8);
    std::vector<std::thread> writers;
    std::vector<std::thread> readers;

    // writers
    for (int i = 0; i < 4; ++i) {
        writers.emplace_back([&ctrl]() {
            std::vector<uint8_t> buf(256, 0xAA);
            for (int j = 0; j < 1000; ++j) {
                uint64_t off = (j * 256) % (ctrl.GetCapacity() - 256);
                bool ok = ctrl.Write(off, buf.data(), buf.size());
                (void)ok;
            }
        });
    }

    // readers
    for (int i = 0; i < 4; ++i) {
        readers.emplace_back([&ctrl]() {
            std::vector<uint8_t> buf(256);
            for (int j = 0; j < 1000; ++j) {
                uint64_t off = (j * 128) % (ctrl.GetCapacity() - 256);
                bool ok = ctrl.Read(off, buf.data(), buf.size());
                (void)ok;
            }
        });
    }

    for (auto &t : writers) t.join();
    for (auto &t : readers) t.join();
}

int main() {
    try {
        TestECC();
        TestRingBufferAndQueue();
        TestControllerConcurrentRW();
    } catch (...) {
        std::cerr << "Test threw exception\n";
        return 2;
    }
    std::cout << "All tests passed\n";
    return 0;
}

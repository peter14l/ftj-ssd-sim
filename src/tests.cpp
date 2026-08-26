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
    (void)res;

    // flip one bit -> should be corrected
    uint64_t flipped = data ^ (1ULL << 5);
    res = FTJController::DecodeAndCorrect(flipped, ecc);
    assert(res == 1);
    (void)res;

    // flip two bits -> uncorrectable (most likely)
    uint64_t dbl = data ^ (1ULL << 5) ^ (1ULL << 10);
    res = FTJController::DecodeAndCorrect(dbl, ecc);
    assert(res == 2);
    (void)res;
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

    // consumer/worker thread: pops from SQ, process, pushes to CQ
    std::thread c([&]() {
        uint32_t processed = 0;
        while (processed < 100) {
            SQEntry req;
            if (qp.PopRequest(req)) {
                CQEntry rsp{req.cid, 0};
                while (!qp.CompleteRequest(rsp)) std::this_thread::yield();
                ++processed;
            } else {
                std::this_thread::yield();
            }
        }
    });

    // reaper: reaps from CQ
    uint32_t reaped = 0;
    while (reaped < 100) {
        CQEntry rx;
        if (qp.Reap(rx)) {
            ++reaped;
        } else {
            std::this_thread::yield();
        }
    }

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

void TestCrossbarPhysics() {
    FTJController ctrl(1024 * 1024, 8);
    auto cfg = ctrl.GetPhysicsConfig();
    cfg.ambient_temp_c = 75.0;
    cfg.enable_ir_drop_sim = true;
    cfg.enable_disturb_tracking = true;
    ctrl.SetPhysicsConfig(cfg);

    // Verify TER ratio calculation
    double ter_75 = ctrl.CalculateTERRatio(75.0);
    assert(ter_75 < 50.0 && ter_75 > 10.0);
    (void)ter_75;

    // Verify IR drop and Merz latency
    double v_eff = ctrl.CalculateEffectiveVoltage(1024 * 64, true);
    assert(v_eff <= cfg.v_applied_write && v_eff > 0.5);
    (void)v_eff;

    double lat = ctrl.CalculateMerzSwitchingLatency(v_eff, true);
    assert(lat >= 300.0);
    (void)lat;

    // Perform writes and verify disturb accumulation & refresh
    std::vector<uint8_t> data(4096, 0x7E);
    for (int i = 0; i < 50; ++i) {
        ctrl.Write(i * 4096, data.data(), data.size());
    }

    auto telem = ctrl.GetPhysicsTelemetry();
    assert(telem.total_half_select_disturbs > 0);
    assert(telem.max_ir_drop_mv > 0.0);
    (void)telem;

    uint64_t refreshed = ctrl.TriggerAutonomousRefresh();
    assert(refreshed > 0);
    (void)refreshed;
}

int main() {
    try {
        std::cout << "Starting TestECC()...\n" << std::flush;
        TestECC();
        std::cout << "TestECC() passed.\n" << std::flush;

        std::cout << "Starting TestRingBufferAndQueue()...\n" << std::flush;
        TestRingBufferAndQueue();
        std::cout << "TestRingBufferAndQueue() passed.\n" << std::flush;

        std::cout << "Starting TestControllerConcurrentRW()...\n" << std::flush;
        TestControllerConcurrentRW();
        std::cout << "TestControllerConcurrentRW() passed.\n" << std::flush;

        std::cout << "Starting TestCrossbarPhysics()...\n" << std::flush;
        TestCrossbarPhysics();
        std::cout << "TestCrossbarPhysics() passed.\n" << std::flush;
    } catch (...) {
        std::cerr << "Test threw exception\n";
        return 2;
    }
    std::cout << "All tests passed\n" << std::flush;
    return 0;
}

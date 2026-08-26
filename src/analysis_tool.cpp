#include "ftj_engine.hpp"
#include <iostream>
#include <vector>
#include <random>
#include <chrono>
#include <iomanip>
#include <fstream>

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

using namespace ftj;

inline uint64_t NowNs() {
#ifdef _WIN32
    #define NOMINMAX
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    LARGE_INTEGER freq, count;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&count);
    return static_cast<uint64_t>((count.QuadPart * 1'000'000'000) / freq.QuadPart);
#else
    return (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::high_resolution_clock::now().time_since_epoch()).count();
#endif
}

struct RunResult {
    std::string name;
    uint64_t logical_bytes;
    uint64_t physical_bytes;
    double duration_s;
    double throughput_mb_s;
    double waf; // physical / logical
};

// Workloads
RunResult Random4KMixed(FTJController &ctrl, size_t logical_capacity, uint64_t num_ops) {
    const size_t BLOCK = 4096;
    std::vector<uint8_t> buf(BLOCK, 0xAA);
    std::mt19937_64 rng(12345);
    std::uniform_int_distribution<uint64_t> dist(0, logical_capacity - BLOCK);
    std::uniform_int_distribution<int> op(1,100);

    uint64_t start = NowNs();
    uint64_t logical = 0;
    for (uint64_t i=0;i<num_ops;++i) {
        uint64_t off = dist(rng);
        if (op(rng) <= 70) {
            ctrl.Read(off, buf.data(), BLOCK);
        } else {
            ctrl.Write(off, buf.data(), BLOCK);
            logical += BLOCK;
        }
    }
    uint64_t end = NowNs();
    uint64_t physical = ctrl.GetTotalPhysicalBytesWritten();
    double dur_s = (end - start) / 1e9;
    double tp = (logical / (1024.0*1024.0)) / dur_s;
    double waf = (logical>0) ? static_cast<double>(physical) / static_cast<double>(logical) : 0.0;
    return {"Random4K_Mixed70_30", logical, physical, dur_s, tp, waf};
}

RunResult SequentialLargeWrites(FTJController &ctrl, size_t logical_capacity, uint64_t num_ops) {
    const size_t BLOCK = 128 * 1024; // 128KB
    std::vector<uint8_t> buf(BLOCK, 0xBB);
    uint64_t logical = 0;
    uint64_t start = NowNs();
    for (uint64_t i=0;i<num_ops;++i) {
        uint64_t off = (i * BLOCK) % (logical_capacity - BLOCK);
        ctrl.Write(off, buf.data(), BLOCK);
        logical += BLOCK;
    }
    uint64_t end = NowNs();
    uint64_t physical = ctrl.GetTotalPhysicalBytesWritten();
    double dur_s = (end - start) / 1e9;
    double tp = (logical / (1024.0*1024.0)) / dur_s;
    double waf = (logical>0) ? static_cast<double>(physical) / static_cast<double>(logical) : 0.0;
    return {"Sequential_128K_Writes", logical, physical, dur_s, tp, waf};
}

// Simple DB WAL-like workload: many small sequential appends (8KB)
RunResult DB_WAL_Append(FTJController &ctrl, size_t logical_capacity, uint64_t num_ops) {
    const size_t BLOCK = 8 * 1024;
    std::vector<uint8_t> buf(BLOCK, 0xCC);
    uint64_t logical = 0;
    uint64_t base = 0;
    uint64_t start = NowNs();
    for (uint64_t i=0;i<num_ops;++i) {
        uint64_t off = (base + (i * BLOCK)) % (logical_capacity - BLOCK);
        ctrl.Write(off, buf.data(), BLOCK);
        logical += BLOCK;
    }
    uint64_t end = NowNs();
    uint64_t physical = ctrl.GetTotalPhysicalBytesWritten();
    double dur_s = (end - start) / 1e9;
    double tp = (logical / (1024.0*1024.0)) / dur_s;
    double waf = (logical>0) ? static_cast<double>(physical) / static_cast<double>(logical) : 0.0;
    return {"DB_WAL_8K_Append", logical, physical, dur_s, tp, waf};
}

int main() {
    std::cout << "ftj_analysis_tool: starting\n" << std::flush;
    // Assumptions and parameters
    const size_t LOGICAL_CAPACITY = 64 * 1024 * 1024; // 64 MiB logical
    const std::vector<double> overprovision = {0.0, 0.07, 0.28, 0.5};
    const uint64_t OPS_RANDOM = 100000; // 100k operations
    const uint64_t OPS_SEQ = 2000; // larger blocks
    const uint64_t OPS_WAL = 20000; // WAL appends

    std::vector<std::string> report_lines;
    report_lines.push_back("FTJ Analysis Report\n");
    report_lines.push_back("Logical capacity: 64 MiB\n");

    int run_index = -1;
    if (__argc > 1) {
        try {
            run_index = std::stoi(__argv[1]);
        } catch(...) { run_index = -1; }
    }
    for (size_t idx = 0; idx < overprovision.size(); ++idx) {
        if (run_index >= 0 && static_cast<int>(idx) != run_index) continue;
        double opct = overprovision[idx];
        size_t phys_cap = static_cast<size_t>(static_cast<double>(LOGICAL_CAPACITY) * (1.0 + opct));
        // Round physical capacity up to PAGE_SIZE for safety
        const size_t PAGE_SIZE = 4096;
        if (phys_cap % PAGE_SIZE != 0) phys_cap = ((phys_cap + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
        std::cout << "\n== Running workloads with overprovisioning=" << (opct*100.0) << "% (phys=" << phys_cap << ") ==\n" << std::flush;
        // Recreate controller per sweep
        std::cout << "Creating FTJController (phys_cap=" << phys_cap << ")..." << std::flush;
        FTJController ctrl(phys_cap, 8);
        std::cout << " created. Calling LatencyInjector::Calibrate()..." << std::flush;
        LatencyInjector::Calibrate();
        std::cout << " calibrated.\n" << std::flush;

        // Reset counters are implicit with new controller
        std::cout << " Starting Random4K_Mixed workload..." << std::flush;
        auto r1 = Random4KMixed(ctrl, LOGICAL_CAPACITY, OPS_RANDOM);
        report_lines.push_back("[OP=" + std::to_string(static_cast<int>(opct*100)) + "%] " + r1.name + ": logical_bytes=" + std::to_string(r1.logical_bytes) + ", physical_bytes=" + std::to_string(r1.physical_bytes) + ", waf=" + std::to_string(r1.waf) + ", tp=" + std::to_string(r1.throughput_mb_s) + " MB/s\n");
        std::cout << " -> " << r1.name << ": WAF=" << r1.waf << ", TP=" << r1.throughput_mb_s << " MB/s\n";

        // Recreate controller to isolate workloads
        FTJController ctrl2(phys_cap, 8);
        std::cout << " Starting SequentialLargeWrites workload..." << std::flush;
        LatencyInjector::Calibrate();
        auto r2 = SequentialLargeWrites(ctrl2, LOGICAL_CAPACITY, OPS_SEQ);
        report_lines.push_back("[OP=" + std::to_string(static_cast<int>(opct*100)) + "%] " + r2.name + ": logical_bytes=" + std::to_string(r2.logical_bytes) + ", physical_bytes=" + std::to_string(r2.physical_bytes) + ", waf=" + std::to_string(r2.waf) + ", tp=" + std::to_string(r2.throughput_mb_s) + " MB/s\n");
        std::cout << " -> " << r2.name << ": WAF=" << r2.waf << ", TP=" << r2.throughput_mb_s << " MB/s\n";

        FTJController ctrl3(phys_cap, 8);
        LatencyInjector::Calibrate();
        auto r3 = DB_WAL_Append(ctrl3, LOGICAL_CAPACITY, OPS_WAL);
        report_lines.push_back("[OP=" + std::to_string(static_cast<int>(opct*100)) + "%] " + r3.name + ": logical_bytes=" + std::to_string(r3.logical_bytes) + ", physical_bytes=" + std::to_string(r3.physical_bytes) + ", waf=" + std::to_string(r3.waf) + ", tp=" + std::to_string(r3.throughput_mb_s) + " MB/s\n");
        std::cout << " -> " << r3.name << ": WAF=" << r3.waf << ", TP=" << r3.throughput_mb_s << " MB/s\n";

        // Extrapolate TBW/day at observed physical write rate
        double phys_bytes = static_cast<double>(r1.physical_bytes + r2.physical_bytes + r3.physical_bytes);
        double dur_s = r1.duration_s + r2.duration_s + r3.duration_s;
        double phys_b_per_s = (dur_s > 0.0) ? phys_bytes / dur_s : 0.0;
        double per_day_tb = phys_b_per_s * 86400.0 / 1e12;
        report_lines.push_back("[OP=" + std::to_string(static_cast<int>(opct*100)) + "%] Estimated_physical_TBW_per_day=" + std::to_string(per_day_tb) + " TB/day\n");
        std::cout << " -> Estimated physical TB/day = " << std::fixed << std::setprecision(6) << per_day_tb << " TB/day\n";

        // Simple lifetime estimate: given endurance target (FTJ model infinite; compare to NAND baseline)
        // For demonstration assume NAND endurance 3k P/E cycles and device size equal to logical capacity.
        double nand_endurance_cycles = 3000.0;
        double device_bytes = static_cast<double>(LOGICAL_CAPACITY);
        double nand_tbw_total = (device_bytes * nand_endurance_cycles) / 1e12; // TB total
        double years_nand = (per_day_tb > 0.0) ? (nand_tbw_total / (per_day_tb * 365.0)) : 0.0;
        report_lines.push_back("[OP=" + std::to_string(static_cast<int>(opct*100)) + "%] NAND_estimated_years_at_this_load=" + std::to_string(years_nand) + " years\n");
        std::cout << " -> (For reference) Equivalent NAND lifetime (3k P/E) = " << std::fixed << std::setprecision(3) << years_nand << " years\n";
    }

    // Cost model (very simple parametric model)
    // Inputs (example): fabric_cost_per_die, bits_per_die, controller_bom_per_device
    double fabric_cost_mature = 2.0; // $ per Gb (example)
    double fabric_cost_advanced = 5.0; // $ per Gb
    double controller_bom = 10.0; // $ per device
    double capacity_gb = 0.064; // 64 MiB ~ 0.064 GB

    report_lines.push_back("\nCOST MODEL (sample assumptions):\n");
    report_lines.push_back("fabric_cost_per_GB_mature=$" + std::to_string(fabric_cost_mature) + ", advanced=$" + std::to_string(fabric_cost_advanced) + "\n");

    double cost_per_device_mature = fabric_cost_mature * capacity_gb + controller_bom;
    double cost_per_gb_mature = cost_per_device_mature / capacity_gb;
    double cost_per_device_adv = fabric_cost_advanced * capacity_gb + controller_bom;
    double cost_per_gb_adv = cost_per_device_adv / capacity_gb;

    report_lines.push_back("Estimated cost per device (mature node) = $" + std::to_string(cost_per_device_mature) + " => $/GB=" + std::to_string(cost_per_gb_mature) + "\n");
    report_lines.push_back("Estimated cost per device (advanced node) = $" + std::to_string(cost_per_device_adv) + " => $/GB=" + std::to_string(cost_per_gb_adv) + "\n");

    // Combine TBW/day with cost to form a naive ROI metric: $/TB_written_per_day (lower is better)
    // Use the earlier per_day_tb from the last overprovisioning loop (take op=0.07 entry approx)
    double sample_per_day_tb = 0.0; // find first non-zero
    // parse report_lines to find per_day_tb entries
    for (const auto &ln : report_lines) {
        auto pos = ln.find("Estimated_physical_TBW_per_day=");
        if (pos != std::string::npos) {
            std::string val = ln.substr(pos + strlen("Estimated_physical_TBW_per_day="));
            try {
                sample_per_day_tb = std::stod(val);
                break;
            } catch(...) {}
        }
    }
    if (sample_per_day_tb > 0.0) {
        double cost_per_tb_mature = cost_per_gb_mature * 1024.0; // $/TB
        report_lines.push_back("Sample workload -> cost per TB (mature) = $" + std::to_string(cost_per_tb_mature) + "\n");
        report_lines.push_back("Sample workload -> per-day TB written = " + std::to_string(sample_per_day_tb) + " TB/day\n");
        report_lines.push_back("Sample workload -> $ cost to write one day worth of TB (mature) = $" + std::to_string(cost_per_tb_mature * sample_per_day_tb) + "\n");
    }

    // Write report to docs/ANALYSIS_RESULTS.md
    std::ofstream ofs("docs/ANALYSIS_RESULTS.md");
    if (ofs.is_open()) {
        ofs << "# FTJ Analysis Results\n\n";
        for (const auto &l : report_lines) ofs << l;
        ofs.close();
        std::cout << "\n[Info] Analysis written to docs/ANALYSIS_RESULTS.md\n";
    } else {
        std::cout << "[Warning] Failed to write docs/ANALYSIS_RESULTS.md\n";
    }

    return 0;
}

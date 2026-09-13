// Copyright (c) 2026 HyperRAM Project. All Rights Reserved.
// Native Windows 24x7 Background Memory Optimizer & Compactor for Low-RAM PCs (4GB/8GB)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <chrono>
#include <thread>
#include <atomic>
#include <csignal>

namespace {
    std::atomic<bool> g_running{true};

    void SignalHandler(int) {
        g_running = false;
    }

    void SetColor(int color) {
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), static_cast<WORD>(color));
    }
}

struct SystemRAMInfo {
    DWORD memory_load_pct;
    double total_phys_gb;
    double avail_phys_gb;
    double used_phys_gb;
};

SystemRAMInfo GetRAMStatus() {
    MEMORYSTATUSEX mem{};
    mem.dwLength = sizeof(mem);
    GlobalMemoryStatusEx(&mem);

    SystemRAMInfo info;
    info.memory_load_pct = mem.dwMemoryLoad;
    info.total_phys_gb = static_cast<double>(mem.ullTotalPhys) / (1024.0 * 1024.0 * 1024.0);
    info.avail_phys_gb = static_cast<double>(mem.ullAvailPhys) / (1024.0 * 1024.0 * 1024.0);
    info.used_phys_gb  = info.total_phys_gb - info.avail_phys_gb;
    return info;
}

// Get PID of current active foreground window so we don't disrupt active typing/gaming
DWORD GetForegroundPID() {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return 0;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    return pid;
}

// Compacts working set across accessible background processes
size_t PerformWorkingSetCompaction(DWORD skip_pid = 0) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 pe{};
    pe.dwSize = sizeof(pe);

    size_t processes_compacted = 0;
    DWORD my_pid = GetCurrentProcessId();

    if (Process32First(snapshot, &pe)) {
        do {
            // Skip kernel idle, current process, and the active foreground app
            if (pe.th32ProcessID <= 4 || pe.th32ProcessID == my_pid || pe.th32ProcessID == skip_pid) {
                continue;
            }

            HANDLE hProcess = OpenProcess(PROCESS_SET_QUOTA | PROCESS_QUERY_INFORMATION, FALSE, pe.th32ProcessID);
            if (hProcess) {
                if (EmptyWorkingSet(hProcess)) {
                    processes_compacted++;
                }
                CloseHandle(hProcess);
            }
        } while (Process32Next(snapshot, &pe));
    }

    CloseHandle(snapshot);
    return processes_compacted;
}

void PrintBanner() {
    SetColor(11); // Cyan
    std::cout << R"(
    ======================================================================
      _   _                         ____       _    __  __ 
     | | | |_   _ _ __   ___ _ __  |  _ \     / \  |  \/  |
     | |_| | | | | '_ \ / _ \ '__| | |_) |   / _ \ | |\/| |
     |  _  | |_| | |_) |  __/ |    |  _ <   / ___ \| |  | |
     |_| |_|\__, | .__/ \___|_|    |_| \_\ /_/   \_\_|  |_|
            |___/|_|                                        
      HyperRAM 24x7 Real-Time Background Memory Daemon v2.0
      Zero-Swap Anti-Freeze Engine for 4GB / 8GB Windows 11 Systems
    ======================================================================
    )" << "\n";
    SetColor(7);
}

int main(int argc, char* argv[]) {
    std::signal(SIGINT, SignalHandler);
    std::signal(SIGTERM, SignalHandler);

    // Set console title
    SetConsoleTitleA("HyperRAM 24x7 Real-Time Memory Compactor");

    bool continuous_mode = true;
    DWORD threshold_pct = 78; // Auto-compact when memory load >= 78%
    double min_avail_gb = 0.85; // Or when free RAM < 850 MB

    // Command line flags: --once, --threshold <pct>, --min-free <mb>
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--once") {
            continuous_mode = false;
        } else if (arg == "--threshold" && i + 1 < argc) {
            threshold_pct = static_cast<DWORD>(std::stoul(argv[++i]));
        } else if (arg == "--min-free" && i + 1 < argc) {
            min_avail_gb = std::stod(argv[++i]) / 1024.0;
        }
    }

    PrintBanner();

    SystemRAMInfo init_info = GetRAMStatus();
    std::cout << "[*] Hardware Memory Detected: " << std::fixed << std::setprecision(2) 
              << init_info.total_phys_gb << " GB Total (" 
              << init_info.avail_phys_gb << " GB Usable Free)\n";
    std::cout << "[*] Operating Mode: " << (continuous_mode ? "24x7 Continuous Background Monitor" : "Single Shot") << "\n";
    std::cout << "[*] Compaction Triggers: Memory Load >= " << threshold_pct << "% OR Available RAM < " 
              << std::fixed << std::setprecision(0) << (min_avail_gb * 1024.0) << " MB\n";
    std::cout << "----------------------------------------------------------------------\n\n";

    // Immediate initial compaction pass
    std::cout << "[*] Performing initial memory compaction pass...\n";
    DWORD fg_pid = GetForegroundPID();
    size_t count = PerformWorkingSetCompaction(fg_pid);
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    SystemRAMInfo post_init = GetRAMStatus();
    double freed_mb = (post_init.avail_phys_gb - init_info.avail_phys_gb) * 1024.0;
    if (freed_mb < 0) freed_mb = 0;

    SetColor(10); // Green
    std::cout << "[+] Initial Pass: Recovered " << std::fixed << std::setprecision(1) 
              << freed_mb << " MB | Current Free RAM: " 
              << post_init.avail_phys_gb << " GB (" 
              << (100 - post_init.memory_load_pct) << "% Headroom)\n\n";
    SetColor(7);

    if (!continuous_mode) {
        std::cout << "Single-pass complete. Exiting.\n";
        return 0;
    }

    std::cout << "[+] 24x7 Monitoring active. Press Ctrl+C in this terminal to stop.\n";
    std::cout << "----------------------------------------------------------------------\n";

    uint64_t cycle_count = 0;
    uint64_t total_compactions = 1;
    double cumulative_freed_mb = freed_mb;

    auto last_compact_time = std::chrono::steady_clock::now();

    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(2));
        cycle_count++;

        SystemRAMInfo cur = GetRAMStatus();
        auto now = std::chrono::steady_clock::now();
        double sec_since_last = std::chrono::duration<double>(now - last_compact_time).count();

        bool needs_compact = (cur.memory_load_pct >= threshold_pct) || 
                             (cur.avail_phys_gb < min_avail_gb) ||
                             (sec_since_last > 120.0); // Periodic clean every 2 mins

        if (needs_compact && sec_since_last >= 5.0) { // Cooldown of 5s
            DWORD active_pid = GetForegroundPID();
            size_t compacted = PerformWorkingSetCompaction(active_pid);
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            SystemRAMInfo after = GetRAMStatus();

            double recovered = (after.avail_phys_gb - cur.avail_phys_gb) * 1024.0;
            if (recovered < 0) recovered = 0;
            cumulative_freed_mb += recovered;
            total_compactions++;
            last_compact_time = std::chrono::steady_clock::now();

            // Format timestamp
            auto now_c = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
            struct tm timeinfo{};
            localtime_s(&timeinfo, &now_c);

            std::cout << "[" << std::setfill('0') << std::setw(2) << timeinfo.tm_hour << ":"
                      << std::setw(2) << timeinfo.tm_min << ":"
                      << std::setw(2) << timeinfo.tm_sec << "] ";

            SetColor(14); // Yellow
            std::cout << "[TRIGGERED] ";
            SetColor(7);

            std::cout << "Load: " << cur.memory_load_pct << "% -> " << after.memory_load_pct << "% | "
                      << "Freed: +" << std::fixed << std::setprecision(1) << recovered << " MB | "
                      << "Available RAM: ";
            SetColor(10);
            std::cout << after.avail_phys_gb << " GB\n";
            SetColor(7);
        } else if (cycle_count % 15 == 0) {
            // Heartbeat status every 30s
            auto now_c = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
            struct tm timeinfo{};
            localtime_s(&timeinfo, &now_c);

            std::cout << "[" << std::setfill('0') << std::setw(2) << timeinfo.tm_hour << ":"
                      << std::setw(2) << timeinfo.tm_min << ":"
                      << std::setw(2) << timeinfo.tm_sec << "] ";
            std::cout << "[HEARTBEAT] Load: " << cur.memory_load_pct << "% | "
                      << "Available RAM: " << std::fixed << std::setprecision(2) << cur.avail_phys_gb << " GB | "
                      << "Total Auto-Compactions: " << total_compactions << "\n";
        }
    }

    SetColor(11);
    std::cout << "\n[!] 24x7 Daemon stopping gracefully...\n";
    std::cout << "    - Lifetime Total Compaction Events: " << total_compactions << "\n";
    std::cout << "    - Estimated Total Memory Recycled:  " << std::fixed << std::setprecision(1) << cumulative_freed_mb << " MB\n";
    SetColor(7);

    return 0;
}


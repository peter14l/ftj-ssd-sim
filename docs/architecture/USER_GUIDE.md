# FTJ Memory Simulator User Guide

This guide provides instructions on how to build, run, and interact with the Ferroelectric Tunnel Junction (FTJ) Memory Engine Simulator on Windows.

---

## 1. Prerequisites

Before building the simulator, ensure your system has the following installed:
1. **CMake** (v3.15 or newer)
2. **C++20 Compiler**:
   - Visual Studio 2019/2022 (MSVC) with the "Desktop development with C++" workload.
   - Alternatively, **Clang** or **MinGW GCC** (configured with C++20 support).

---

## 2. Building the Project

We provide an automated PowerShell script to configure and compile the engine:

1. Open a PowerShell terminal.
2. Navigate to the project root directory.
3. Run the build script:
   ```powershell
   .\build.ps1
   ```

Upon completion, compiled executables will be located in the `build/` or `build/Release/` directory:
- `ftj_sim_cli.exe`: CLI Performance and Comparison Benchmark Suite.
- `ftj_vdisk_srv.exe`: Virtual Disk Named Pipe Service.

---

## 3. Running the Benchmark Suite

To run the performance metrics and 3D NAND comparative benchmarks:
```cmd
.\build\Release\ftj_sim_cli.exe
```

This tool outputs real-time latency summaries to the console and outputs detailed markdown statistics to `docs/BENCHMARK_RESULTS.md`.

---

## 4. Using the Virtual Disk Interface

The Virtual Disk Server exposes the physical FTJ Controller via a Windows Named Pipe (`\\.\pipe\FTJ_Sim_Disk`) to enable low-overhead, user-space virtual block device simulation.

1. Start the Virtual Disk Server:
   ```cmd
   .\build\Release\ftj_vdisk_srv.exe
   ```
2. Client applications can communicate with this pipe using standard Win32 `CreateFile` / `WriteFile` / `ReadFile` APIs to perform byte-addressable operations with exact 8ns latency injection.

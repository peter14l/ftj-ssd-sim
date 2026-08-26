# Project Progress Checklist

## Progress Log
- [x] Repository Initialized

## Stage 2: Core Engine Development
1. [x] Implement the `FtjMemoryController` (implemented as `FTJController`) core class and backing store management.
2. [x] Develop the `LatencyInjector` class with Windows high-resolution timer (`QueryPerformanceCounter`) logic for 8ns delays.
3. [x] Implement the `NvmeQueuePair` circular rings with lock-free submission and completion logic.
4. [x] Build the background execution engine thread pool to process SQEs and produce CQEs.
5. [x] Write unit tests for memory operations, queue concurrency, and latency injection accuracy.

## Stage 3: CLI & Benchmarks
6. [x] Implement the CLI executable framework for runtime configuration options.
7. [x] Build the synthetic workload generator supporting random/sequential reads and writes.
8. [x] Design the statistics tracking engine to calculate IOPS and Throughput (GB/s).
9. [x] Implement the high-resolution latency histogram generator (min, max, average, p99, p99.9, p99.99).
10. [x] Add support for automated Queue Depth sweeps.

## Stage 4: Virtual Disk Integration
11. [x] Research Windows storage driver interfaces (e.g., Storport or virtual disk interfaces/Storport Miniport/UMDF/ImDisk-like virtual disk mounts).
12. [x] Develop a user-mode virtual disk driver wrapper or mount interface mapping Windows file-system reads/writes directly to the simulated FTJ memory engine.
13. [x] Perform compatibility testing with standard file systems (NTFS/FAT32).
14. [x] Run full system benchmarks using standard disk benchmarking tools (CrystalDiskMark, FIO) on the mounted virtual disk.

## Stage 5: Silicon & Hardware Realism Engine
15. [x] Develop 2D Crossbar Array wire resistance mesh solver & IR-Drop attenuation calculation.
16. [x] Implement Merz's Law dynamic non-linear polarization switching kinetics.
17. [x] Implement Tunnel Electroresistance (TER) sensing margin degradation and Arrhenius temperature retention models (25°C to 125°C).
18. [x] Model 1S-1R threshold selector non-linear current leakage and sneak-path suppression.
19. [x] Build Half-Select Disturb stress tracking and autonomous Hardware Autonomous Refresh State Machine (HAR-SM) in RTL (`hdl/ftj_top_controller.v`).
20. [x] Add Analog Front-End (AFE) Current Sense Amplifier models in Verilog and full physics telemetry suite in CLI.

## Created Files Summary
- [`include/ftj_engine.hpp`](file:///D:/FTJ-SSD-Sim/include/ftj_engine.hpp): Header defining the `FTJController` and `LatencyInjector` classes with TSC-based low-overhead nanosecond latency injection, 2D crossbar IR-drop solver, Merz's law switching kinetics, and disturb tracking.
- [`src/ftj_engine.cpp`](file:///D:/FTJ-SSD-Sim/src/ftj_engine.cpp): Implementation of the physical FTJ memory simulation, crossbar array physics, temperature TER drift, and high-precision timer calibration on Windows.
- [`src/main.cpp`](file:///D:/FTJ-SSD-Sim/src/main.cpp): Windows CLI entry point executing synthetic workloads, comparing simulated FTJ against 3D NAND, and running crossbar physics telemetry benchmarks.
- [`src/tests.cpp`](file:///D:/FTJ-SSD-Sim/src/tests.cpp): Unit tests for memory operations, queue concurrency, ECC error correction, and crossbar physics / IR-drop dynamics.
- [`hdl/ftj_top_controller.v`](file:///D:/FTJ-SSD-Sim/hdl/ftj_top_controller.v): Synthesizable top-level hardware controller with SECDED 72/64 ECC, Analog Front-End (AFE) sensing, and Hardware Autonomous Refresh State Machine (HAR-SM).
- [`src/win_vdisk.cpp`](file:///D:/FTJ-SSD-Sim/src/win_vdisk.cpp): Implementation of the virtual disk server exposing the FTJ device mapping to Win32 Named Pipes.
- [`CMakeLists.txt`](file:///D:/FTJ-SSD-Sim/CMakeLists.txt): CMake build definition configured to output the CLI executable target.
- [`build.ps1`](file:///D:/FTJ-SSD-Sim/build.ps1): Automated PowerShell build and compiler detection script.
- [`docs/USER_GUIDE.md`](file:///D:/FTJ-SSD-Sim/docs/USER_GUIDE.md): Instruction manual detailing compilation and execution processes.
- [`docs/BENCHMARK_RESULTS.md`](file:///D:/FTJ-SSD-Sim/docs/BENCHMARK_RESULTS.md): Markdown file displaying latency comparison reports and metrics.
- [`docs/ARCHITECTURE.md`](file:///D:/FTJ-SSD-Sim/docs/ARCHITECTURE.md): Comprehensive architectural specification detailing solid-state physics, crossbar arrays, and hardware state machines.
- [`docs/EXECUTIVE_SUMMARY.md`](file:///D:/FTJ-SSD-Sim/docs/EXECUTIVE_SUMMARY.md): Formal grant/commercialization proposal detailing the mature-node economic strategy and FTJ memory controller.
- [`docs/PITCH_DECK_OUTLINE.md`](file:///D:/FTJ-SSD-Sim/docs/PITCH_DECK_OUTLINE.md): 10-slide startup pitch presentation outline for venture capital partners.

## WinFSP SDK Verification Log
- **Status**: Completed! Verified WinFSP SDK headers at `C:\Program Files (x86)\WinFsp\inc\winfsp\winfsp.h`, integrated FSP dispatch handlers in `src/win_vdisk.cpp`, configured `winfsp-x64.lib` in `CMakeLists.txt`, and automated post-build copying of `winfsp-x64.dll` to target build folders.
- **Verification**: Fixed `0xc000000e` (STATUS_NO_SUCH_DEVICE) error by adding dynamic driver initialization via `FspLoad(NULL)`. Resolved the "Incorrect function" (`STATUS_INVALID_DEVICE_REQUEST`) error by setting the structure size version `VolumeParams.Version = sizeof(FSP_FSCTL_VOLUME_PARAMS)` and adopting the official `FspServiceRun` daemon host wrapper. Implemented full read/write/delete/rename interception logic in `src/win_vdisk.cpp` matching the `memfs` model. Pre-created the simulated virtual disk file `ftj_disk.bin` (128 MB) inside the directory. Fully tested and verified that running the server via `ftj_vdisk_srv.exe -m Y:` mounts the drive as `Y:` under the volume label `FTJFS` and makes `ftj_disk.bin` completely listable and accessible!

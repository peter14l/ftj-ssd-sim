# FTJ-SSD-Sim — Ferroelectric Tunnel Junction Memory Engine Simulator

> **One-line pitch:** A flight simulator for a new kind of memory chip — plus the actual synthesizable chip design.

**Copyright © 2026 Shreyas Sengupta. All Rights Reserved. Proprietary & Confidential.**

---

## 💡 What Is This? (Start Here)

Today's SSDs (solid-state drives) use **NAND Flash** memory, which has three fundamental problems:
- **They wear out** — each cell can only be written ~3,000 times before it fails.
- **They can't overwrite data directly** — to update a single byte, the drive must erase an entire 4 MB block first, causing multi-millisecond "stutter" spikes.
- **They are slow** — reads take ~25 µs, writes take ~100 µs.

**Ferroelectric Tunnel Junction (FTJ)** memory solves all three problems at the physics level:
- Stores data using the *polarization direction* of a nanometre-thin hafnium oxide (HfO₂) layer — a quantum tunnelling effect, not trapped electrons.
- Supports **unlimited write cycles**, **direct byte-level overwrites** (no erase needed), and **8 ns read/write latency**.
- Compatible with existing **28 nm CMOS foundries** (cheap, proven, available today).

This repository is the **complete software simulation and synthesizable RTL hardware design** for an FTJ-based SSD controller IP block — built toward a SandForce-model IP licensing exit.

---

## 📊 Benchmark Results (Measured, Not Theoretical)

| Metric | Regular 3D NAND SSD | This FTJ Simulator | Improvement |
|:---|:---:|:---:|:---:|
| Read latency (cell) | ~25 µs | **8 ns** | **~3,100×** |
| Write latency (cell) | ~100 µs | **300 ns** | **~333×** |
| Block erase overhead | ~3 ms | **0 ms** | **Eliminated** |
| Write endurance (per cell) | ~3,000 cycles | **>10 Billion** | **>3,000,000×** |
| Random 4K IOPS (virtual disk) | — | **205,000 IOPS** | — |
| Throughput (virtual disk) | — | **801 MiB/s** | — |
| Avg latency (virtual disk) | — | **6.8 µs** | — |
| Write amplification (FTJ vs NAND) | 312 block erases | **0 block erases** | **489× less WAF** |
| Compression ratio (sparse AI tensors) | N/A | **6.6× (BDI pipeline)** | — |

> Benchmark source: [`docs/benchmarks/BENCHMARK_RESULTS.md`](docs/benchmarks/BENCHMARK_RESULTS.md) and [`docs/benchmarks/ANALYSIS_RESULTS.md`](docs/benchmarks/ANALYSIS_RESULTS.md)

---

## 🏗️ System Architecture

The project is split into four tightly integrated layers:

```
┌──────────────────────────────────────────────────────────────┐
│                      HOST (Windows / OS)                     │
│  CrystalDiskMark, FIO, custom benchmark workloads            │
└───────────────────────────┬──────────────────────────────────┘
                            │  NTFS / FAT32 file-system I/O
┌───────────────────────────▼──────────────────────────────────┐
│              VIRTUAL DISK LAYER  (WinFSP)                    │
│  win_vdisk.cpp + win_vdisk_srv.c  →  Drive Y: (FTJFS)        │
│  Named-pipe dispatch, FspServiceRun host, read/write/rename  │
└───────────────────────────┬──────────────────────────────────┘
                            │  Internal C++ API calls
┌───────────────────────────▼──────────────────────────────────┐
│              SIMULATION ENGINE LAYER  (C++20)                │
│  FTJController  — Merz's Law switching kinetics              │
│  NvmeQueuePair  — Lock-free MPMC ring buffers (Vyukov algo)  │
│  LatencyInjector — TSC-based 8 ns hardware latency model     │
│  Crossbar IR-Drop Solver — 2D mesh wire resistance           │
│  HAR-SM — Hardware Autonomous Refresh State Machine          │
│  SECDED ECC — Hamming (72,64) single-bit correct / DBE detect│
│  WAF Harness — Write Amplification Factor analysis           │
└───────────────────────────┬──────────────────────────────────┘
                            │  AXI4 interface (RTL simulation)
┌───────────────────────────▼──────────────────────────────────┐
│              RTL / HARDWARE DESIGN LAYER  (Verilog)          │
│                                                              │
│  ftj_chip_top.v ← Top-level integration wrapper             │
│  │                                                           │
│  ├── ftj_bdi_encoder.v    BDI 64-bit word compression       │
│  │     TYPE_ZERO (8→1B) │ UNIFORM (8→2B) │ BASE4 (8→6B)    │
│  │                                                           │
│  ├── ftj_word_serializer.v  64-bit → byte stream FSM        │
│  │                                                           │
│  ├── ftj_compressor.v    Zero-suppression RLE compressor    │
│  │                                                           │
│  ├── ftj_byte_assembler.v   Byte stream → 64-bit word FSM   │
│  │                                                           │
│  ├── ftj_top_controller.v   AXI4 memory controller          │
│  │     ECC │ GC │ FTL L2P map │ AFE sense amp │ HAR-SM      │
│  │                                                           │
│  └── ftj_submission_queue.v  NVMe SQ ring buffer            │
│                                                              │
│  verif/uvm/   Full UVM verification suite                    │
│  scripts/     Yosys synthesis + SDC constraints              │
└──────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Repository Structure

```
FTJ-SSD-Sim/
│
├── include/
│   └── ftj_engine.hpp          Core C++ header: FTJController, LatencyInjector,
│                                NvmeQueuePair, crossbar IR-drop, TER models
│
├── src/
│   ├── ftj_engine.cpp          Physics simulation: Merz's Law, crossbar mesh,
│   │                            temperature drift, Vyukov MPMC queues, TSC timers
│   ├── main.cpp                CLI entry point: synthetic workloads, benchmark
│   │                            runner, terminal TUI, crossbar telemetry
│   ├── tests.cpp               Unit tests: ECC, queue concurrency, IR-drop,
│   │                            half-select disturb, wear-out at 130% endurance
│   ├── waf_harness.cpp         Write Amplification Factor analysis tool
│   ├── win_vdisk.cpp           WinFSP virtual disk server (2653 lines):
│   │                            FspServiceRun, read/write/rename/delete handlers
│   └── win_vdisk_srv.c         Virtual disk client entry point (mount Y:)
│
├── hdl/                        ← Synthesizable RTL (28 nm-compatible)
│   ├── ftj_chip_top.v          Top-level chip: full 4-stage write-path pipeline
│   ├── ftj_bdi_encoder.v       64-bit Base-Delta-Immediate compression (comb.)
│   ├── ftj_word_serializer.v   64b word → byte stream FSM (AXI-stream)
│   ├── ftj_compressor.v        Zero-suppression RLE byte-stream compressor
│   ├── ftj_byte_assembler.v    Byte stream → 64b word reassembler (wstrb)
│   ├── ftj_top_controller.v    AXI4 controller: ECC, GC, FTL, AFE, HAR-SM
│   ├── ftj_submission_queue.v  Circular FIFO NVMe submission queue
│   ├── nand_flash_model.v      NAND Flash behavioral model for simulation
│   ├── nvme_flash_if.sv        NVMe ↔ Flash interface
│   ├── tb_ftj_stage6.v         Stage 6 verification: 9 tests, all PASS
│   ├── tb_ftj_compressor.v     Compressor testbench: 4 tests, all PASS
│   ├── tb_ftj_top_controller.v Controller testbench
│   └── tb_ftj_submission_queue.v Queue testbench
│
├── verif/uvm/                  Full UVM verification suite
│   ├── ftj_agent.sv            UVM agent
│   ├── ftj_driver.sv           UVM driver
│   ├── ftj_monitor.sv          UVM monitor
│   ├── ftj_scoreboard.sv       UVM scoreboard
│   ├── ftj_sequence.sv         UVM sequence
│   ├── ftj_sequencer.sv        UVM sequencer
│   ├── ftj_transaction.sv      UVM transaction
│   └── tb_top.sv               UVM testbench top
│
├── scripts/
│   ├── synthesize.ys           Yosys synthesis script (top: ftj_chip_top)
│   ├── ftj_controller_constraints.sdc  Timing constraints
│   ├── run_synthesis.sh        Linux/WSL synthesis runner
│   └── output/                 Netlist + PPA report (generated)
│
├── docs/
│   ├── architecture/ARCHITECTURE.md    Full physics + RTL architecture spec
│   ├── benchmarks/BENCHMARK_RESULTS.md Measured IOPS, latency, WAF numbers
│   ├── benchmarks/ANALYSIS_RESULTS.md  WAF cost model, OP spacing analysis
│   ├── pitch_and_grants/
│   │   ├── EXECUTIVE_SUMMARY.md        Grant/commercialisation proposal
│   │   ├── PITCH_FAQ.md                Plain-English investor Q&A
│   │   └── PITCH_DECK_OUTLINE.md       10-slide VC pitch outline
│   └── USER_GUIDE.md                   Build and run instructions
│
├── build/Release/              ← Prebuilt Windows binaries
│   ├── ftj_sim_cli.exe         Main benchmark CLI + TUI
│   ├── ftj_tests.exe           Unit test runner
│   ├── ftj_analysis_tool.exe   WAF + cost model analysis
│   └── ftj_waf_harness.exe     Write amplification harness
│
├── PROGRESS.md                 Stage-by-stage development checklist
├── CMakeLists.txt              CMake build definition (C++20, MSVC)
├── build.ps1                   Automated PowerShell build script
└── FTJMemorySim.sln            Visual Studio 2022 solution
```

---

## 🔧 Compression Pipeline — Stage 6 Detail

The write path implements a **4-stage hardware compression pipeline** that reduces the number of FTJ cell polarization-switching events (directly extending device lifetime):

```
Host 64-bit AXI write beat
    │
    ▼  Stage A — ftj_bdi_encoder.v (purely combinational)
    │  64-bit BDI compression per word:
    │    TYPE_ZERO    → 1 byte  (8:1)   — sparse activation vectors
    │    TYPE_UNIFORM → 2 bytes (4:1)   — weight-sharing / bias arrays
    │    TYPE_BASE4   → 6 bytes (1.33:1) — clustered INT8 weight rows
    │    TYPE_RAW     → 8 bytes (1:1)   — incompressible data
    │
    ▼  Stage B — ftj_word_serializer.v
    │  Converts the compressed word (1–8 valid bytes) into a
    │  byte stream. Respects AXI-stream back-pressure.
    │
    ▼  Stage C — ftj_compressor.v
    │  Zero-suppression run-length encoding on the byte stream.
    │  On sparse AI tensors: additional 6.6× measured ratio.
    │
    ▼  Stage D — ftj_byte_assembler.v
    │  Reassembles compressed bytes into 64-bit words + wstrb mask.
    │  Partial-burst flush on in_last for correct AXI protocol.
    │
    ▼  ftj_top_controller.v (AXI4 memory controller)
       ECC encode → FTL translate → HAR-SM → NAND/FTJ array
```

**Compression telemetry** (`comp_bytes_in`, `comp_bytes_out`, `comp_ratio_x10`, `bdi_last_type`, `bdi_last_savings_bytes`) is exposed as dedicated output ports wired directly to the C++ benchmark CLI dashboard.

---

## 🔑 Key Technical Concepts (Quick Reference for AI Agents)

| Term | What It Means Here |
|:---|:---|
| **FTJ** | Ferroelectric Tunnel Junction — memory cell using HfO₂ polarization switching |
| **TER** | Tunnel Electroresistance — the ratio of HRS vs LRS current (sensing margin). Modelled vs temperature (25°C–125°C) using Arrhenius equation |
| **Merz's Law** | Non-linear switching kinetics formula: `t_sw = t0 * exp(E_a / E_applied)`. The engine uses this to compute write latency per cell |
| **HAR-SM** | Hardware Autonomous Refresh State Machine — RTL FSM that detects half-select disturb accumulation and restores affected pages autonomously |
| **SECDED (72,64)** | Hamming error-correction code: corrects all single-bit errors, detects all double-bit errors. Implemented in both C++ and Verilog |
| **Vyukov MPMC** | Lock-free multi-producer multi-consumer ring buffer algorithm used for the NVMe Submission/Completion Queue simulation |
| **BDI** | Base-Delta-Immediate — compression algorithm that encodes byte values as (base + small delta). Effective on clustered AI weight tensors |
| **IR-Drop** | Voltage drop across crossbar array wire resistance. The engine solves a 2D mesh model to compute per-cell read margin degradation |
| **WinFSP** | Windows File System Proxy — user-mode file system driver. Used here to expose the FTJ simulator as a real mountable Windows drive (Y:) |
| **28 nm node** | Manufacturing technology target. Mask cost ~$2–3M (vs $50M+ for sub-7 nm), fully compatible with HfO₂ BEOL deposition |
| **AXI4** | ARM AMBA 4 bus protocol used by the RTL controller. Standard interface for FPGA and ASIC SoC integration |

---

## 🛠️ Build and Run

### Requirements
- **OS:** Windows 10/11 64-bit (C++ simulation + virtual disk)
- **Compiler:** Visual Studio 2022 (C++ Desktop Development workload)
- **Build:** CMake 3.15+
- **Optional:** WinFSP SDK (for virtual disk mount), Yosys (for RTL synthesis in WSL)

### Build (Windows)
```powershell
cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

### Run Benchmark CLI
```powershell
.\build\Release\ftj_sim_cli.exe
```

### Run Unit Tests
```powershell
.\build\Release\ftj_tests.exe
```

### Mount as Virtual Disk (Drive Y:)
```powershell
.\build\Release\ftj_vdisk_srv.exe -m Y:
# Windows now sees it as a real drive. Run CrystalDiskMark against Y:.
```

### Simulate RTL (WSL / Linux — requires iverilog)
```bash
# Stage 6 full compression pipeline verification (9 tests)
iverilog -o /tmp/tb_s6.vvp -s tb_ftj_stage6 \
  hdl/ftj_bdi_encoder.v hdl/ftj_word_serializer.v \
  hdl/ftj_byte_assembler.v hdl/ftj_compressor.v hdl/tb_ftj_stage6.v
vvp /tmp/tb_s6.vvp

# Synthesize full chip (requires Yosys)
yosys scripts/synthesize.ys
```

---

## 📈 Development Stage Status

| Stage | Description | Status |
|:---:|:---|:---:|
| 1 | Repository initialisation | ✅ Done |
| 2 | Core simulation engine: FTJController, LatencyInjector, NvmeQueuePair | ✅ Done |
| 3 | CLI, benchmark runner, synthetic workloads, latency histograms | ✅ Done |
| 4 | WinFSP virtual disk (Drive Y:), NTFS compatible, stress tested | ✅ Done |
| 5 | Silicon realism: crossbar IR-drop, Merz's Law, TER drift, HAR-SM, AFE, UVM | ✅ Done |
| 6 | In-line write-path compression: BDI encoder + serializer + compressor + assembler | ✅ Done |
| 7 | FPGA board bring-up (Xilinx Kria / Digilent Nexys) | 🔜 Next |

---

## 📄 IP & Licensing

**Copyright © 2026 Shreyas Sengupta. All Rights Reserved.**

This repository contains **proprietary intellectual property, synthesizable RTL, and patent-pending architectures** for FTJ-based memory controllers and in-line hardware compression engines.

- **Evaluation License:** Permitted for academic research and personal study only.
- **Commercial Restrictions:** ASIC tape-out, FPGA productisation, reverse engineering, redistribution, or sublicensing is **strictly prohibited** without a written license agreement.
- For IP licensing, foundry partnership, or grant inquiries (MeitY TIDE 2.0, DLI Scheme, NIDHI-PRAYAS): contact the repository owner.

See [`LICENSING.md`](LICENSING.md) for complete legal terms.

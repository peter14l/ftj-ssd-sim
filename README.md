# FTJ Memory Engine Simulator

A project simulating how next-generation **Ferroelectric Tunnel Junction (FTJ)** memory works inside solid-state drives (SSDs) and computer storage systems.

---

## 💡 What Is This Project? (The Simple Explanation)

### 1. The Problem With Today's SSDs
* **They wear out:** Modern SSDs (flash drives) degrade every time you write data to them. After too many writes, they stop working.
* **They can't overwrite data easily:** To update a tiny piece of information, a flash SSD has to erase a huge block of data first (which takes a long time and causes sudden slowdowns/lag spikes).

### 2. The Solution (FTJ Memory)
* **Near-infinite lifespan:** FTJ is a new type of memory chip that stores information using tiny electric fields instead of trapping electrons. You can write to it billions of times without wearing it out.
* **Instant overwrites:** It lets the computer write directly to any exact byte of data instantly, without needing slow background erase cycles.

### 3. What This Repository Does
This repository contains a **software simulator and hardware blueprints (Verilog)** that test how fast, reliable, and durable a storage drive would be if it were powered by this new FTJ memory technology.

---

## ⚙️ How It Works (Step-by-Step)

1. **The Fast Lane (Queues):** Incoming read and write requests are placed into a fast, wait-free ring buffer so CPU threads don't block each other.
2. **The Memory Simulator:** The C++ code (`ftj_engine.cpp`) calculates real-world physics: how electric voltage travels through the chip wires, how temperature changes performance, and how long reads and writes take.
3. **Error Protection (SECDED ECC):** If heat or electrical noise ever flips a bit from a `0` to a `1`, the built-in error corrector detects and fixes it automatically.
4. **Hardware Chip Design:** The `hdl/` folder contains actual synthesizable Verilog code that can be loaded onto an FPGA board to test the controller logic in real hardware.

---

## 📊 Quick Performance Comparison

| Feature | Regular Flash SSDs | Simulated FTJ SSD | Why It Matters |
| :--- | :--- | :--- | :--- |
| **Read Speed** | ~25 microseconds (slow) | **8 nanoseconds (instant)** | ~3,000x faster response time |
| **Write Speed** | ~100 microseconds | **300 nanoseconds** | ~300x faster writes |
| **Block Erase Delay** | ~3 milliseconds | **0 ms (None needed)** | Eliminates sudden stutter/lag spikes |
| **Lifespan (Endurance)**| ~3,000 writes per cell | **>10 Billion writes** | Drive won't burn out from constant writes |

---

## 🛠️ How to Build and Run

### Requirements
* **Operating System:** Windows 10 / 11 (64-bit)
* **Compiler:** Visual Studio 2022 (with C++ Desktop Development)
* **Build Tool:** CMake 3.15 or newer
* **Optional:** WinFSP (if you want to mount it as a virtual Windows drive)

### Step 1: Build the Project
Open PowerShell in this folder and run:

```powershell
# Generate Visual Studio solution
cmake -B build -G "Visual Studio 17 2022" -A x64

# Build in Release mode
cmake --build build --config Release
```

### Step 2: Run the Benchmark Suite
To test the speed and error correction:

```powershell
.\build\Release\ftj_sim_cli.exe
```

### Step 3: Run the Live Terminal Dashboard
To see live speed meters and a visual wear-out map:

```powershell
.\build\Release\ftj_sim_cli.exe --tui
```

### Step 4: Open the Graphical Dashboard
Double-click [`docs/dashboard.html`](file:///D:/FTJ-SSD-Sim/docs/dashboard.html) in your browser to view interactive charts, thermal telemetry, and chip data flow.

---

## 📁 Repository Structure

* [`include/ftj_engine.hpp`](file:///D:/FTJ-SSD-Sim/include/ftj_engine.hpp) — Header file defining the controller, queue structures, and physics calculations.
* [`src/ftj_engine.cpp`](file:///D:/FTJ-SSD-Sim/src/ftj_engine.cpp) — Core simulation logic (voltage calculations, error correction, and memory read/write).
* [`src/main.cpp`](file:///D:/FTJ-SSD-Sim/src/main.cpp) — Benchmark tests and the terminal monitor (TUI).
* [`src/tests.cpp`](file:///D:/FTJ-SSD-Sim/src/tests.cpp) — Unit tests for error correction, queues, and multi-threaded read/write safety.
* [`hdl/`](file:///D:/FTJ-SSD-Sim/hdl/) — Verilog hardware designs for FPGA chips (`ftj_top_controller.v`).
* [`docs/`](file:///D:/FTJ-SSD-Sim/docs/) — Documentation, architecture diagrams, and the web dashboard.

---

## 📄 License & IP Notice

Copyright © 2026. All Rights Reserved.  
This project contains proprietary simulation algorithms and hardware controller architectures. For evaluation or academic inquiries, please contact the repository owner.

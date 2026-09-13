# Pitch Guide — Plain-English Codebase & FAQ

Everything you need to pitch this project and answer questions without technical jargon.

---

## The whole project in one sentence

> **"I built a flight simulator for a new kind of memory chip — plus the actual chip design — so we can prove it works before spending millions to manufacture it."**

You can't build a chip cheaply. So you simulate it in software (does everything the real chip would do), test it hard, and write the real hardware blueprint. That's what this repo is.

---

## The problem, in plain English

**Problem 1 — normal SSD memory wears out.** Regular SSDs use "NAND flash" memory. Think of it as a whiteboard you erase and rewrite. Every rewrite slightly damages the surface. After about **3,000 rewrites**, a cell dies. AI workloads (caching, searching databases) write constantly — so normal SSDs die in months.

**Problem 2 — making new chips is a rich man's game.** The most advanced chip factories are owned by a few companies and cost a fortune ($50M+ just for the blueprints/masks). Small teams can't afford it.

**The fix — FTJ memory.** A new memory type that stores data by *flipping a state with an electric field* — like a light switch. Flipping a switch doesn't wear it out. So FTJ survives **>10 billion writes** (vs 3,000), and it's much faster. And it can be made on **old, cheap, widely-available factories** (28nm) using standard materials — no retooling, ~20x cheaper startup cost.

---

## What's in the codebase, one part at a time

| What it's called in the repo | What it really is |
|---|---|
| `include/ftj_engine.hpp` + `src/ftj_engine.cpp` | **The brain.** A program that pretends to be the memory chip: stores data, tracks wear, fixes errors. |
| — "FTL / L2P map / hot-cold / GC" | **The librarian + janitor system.** The chip can't safely rewrite the same spot, so it writes new copies elsewhere and keeps an *index* (catalog) of where everything is. When free space runs low, a *janitor* sweeps out old copies. Frequently-written and rarely-written data are kept in separate rooms so cleanup is efficient. |
| — "ECC" (`CalculateECC`, `DecodeAndCorrect`) | **A spell-checker for data.** If a bit flips (data gets corrupted), it detects and fixes it automatically. |
| — "wear tracking" (`page_writes_`, `GetMaxWearPercentage`) | **A mileage counter per region** of the chip, simulating how long it lasts. |
| `LatencyInjector` | **A stopwatch/waiter.** The real chip takes 8 nanoseconds to read/write. This makes the simulation hold every operation for *exactly* that long, so your measurements are realistic. |
| `LockFreeRingBuffer` + `NVMeQueuePair` | **The conveyor belt.** Commands go in one end (submission queue), results come out the other (completion queue). Many workers can use it at once **without traffic jams** — that's what "lock-free" means. |
| `src/win_vdisk.cpp` + WinFSP | **The storefront.** Instead of a hidden test program, Windows actually sees a real disk — drive **`Y:`** — backed by your simulated chip. Real tools can walk in and use it. |
| `hdl/` (`ftj_submission_queue.v`, `ftj_top_controller.v`, `ftj_ecc_encoder/decoder`, testbenches) | **The actual chip blueprint**, written in Verilog (the language chip engineers use). The `tb_` files are test harnesses that simulate the blueprint to check the logic is right. **This is what an FPGA board would run.** |
| `src/main.cpp` → `ftj_sim_cli.exe` | **The gym + measuring tape.** Runs synthetic workouts (reads/writes at various depths) and records the scores (IOPS, throughput, latency). Has a live dashboard (`--tui`). |
| `src/tests.cpp` → `ftj_tests.exe` | **The exam.** Automatically checks the brain, the spell-checker, and the conveyor belt all work. |
| `src/waf_harness.cpp`, `src/analysis_tool.cpp` | **Cost/wear calculators.** WAF = how much *extra* internal writing happens per byte you write (normal for flash-type memory). |
| `docs/` + `graphify-out/GRAPH_REPORT.md` | Your **business material** (grant proposal, pitch outline, executive summary) and the graph that maps how everything connects. |

---

## How it all connects (the 5-second flow)

1. A program (a benchmark tool, or Windows itself) asks to read/write data → onto the **conveyor belt**.
2. A worker picks it up; the **stopwatch** holds it exactly as long as the real chip would.
3. The **brain** reads/writes its simulated memory, runs the **spell-checker**, updates the **mileage counter**.
4. The result comes back out the other end of the conveyor belt.
5. Because it's mounted as **drive Y:**, real programs (fio, CrystalDiskMark) can hammer it exactly like a real disk — and your benchmarks prove it holds up.

---

## Your numbers, and what they mean in simple terms

- **205,000 IOPS** → your drive answers **205,000 requests every second**.
- **801 MiB/s** → it moves ~**800 MB of data per second**.
- **6.8 µs** → it answers a read in **6.8 millionths of a second**. A normal NVMe SSD takes ~70–90 µs — yours is **~10x faster**.
- **60+ GB of stress traffic, 0 errors** → the spell-checker caught everything; nothing was lost.

---

## Likely questions at a pitch — and your answers

**"What is FTJ?"**
> "A new type of memory that stores data by flipping a state with an electric field — like a light switch. Flipping doesn't wear it out, and it works at memory speed."

**"Why is it better than today's SSD?"**
> "Today's SSD cells die after ~3,000 writes. FTJ survives 10 billion+. And it's about 10x faster to read. AI workloads that kill normal drives in months wouldn't faze it."

**"Why 28nm?"**
> "The newest factories are owned by a few giants and are extremely expensive. FTJ uses standard materials that work on old, cheap, everywhere-available factories — so we can start for a fraction of the usual cost."

**"What have you actually built?"**
> "Two things: (1) a working simulation of the full storage controller — Windows even sees it as a real disk and it benchmarks beautifully — and (2) the actual chip design in Verilog, already verified in simulation."

**"Is it just a simulation?"**
> "The *behavior* is simulated in software. The *chip design* is real — it's the blueprint that would go to a factory. Next step is proving it on real electronic hardware (an FPGA), which is exactly what I'm seeking funding for."

**"Why do you need an FPGA?"**
> "An FPGA is a reprogrammable chip — you can load my design onto it and watch it run on real electronics, for a few hundred dollars, instead of spending millions on a factory run. It's the standard cheap way to prove a chip design works."

**"What do you want?"**
> "Three things: expert feedback on the architecture, guidance on next steps, and funding for an FPGA board to validate the hardware design — plus any leads on grants (NIDHI-PRAYAS, MeitY TIDE)."

**"How do you make money?"**
> "License the controller design (IP) to SSD makers and CXL memory companies, and ultimately manufacture on cheap 28nm. That's Phase 3–4; right now it's prove-the-technology time."

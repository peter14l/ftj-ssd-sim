# CHANGELOG

All notable changes to the FTJ Memory Engine Simulator are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased] — Silicon IP Block Upgrade · 2026-09-02

### Overview
Three-mandate engineering upgrade converting the FTJ research simulator into a
commercially licenseable Silicon IP block targeting mainstream SSD controller
manufacturers (Phison, Silicon Motion, Marvell). Verified on **native Windows 10/11**
— no WSL, Docker, or Linux VM required.

---

### Added

#### Mandate 1 — 3D NAND RTL Compliance & C++ Burst Buffer

**`hdl/nand_flash_model.v`** *(new)*
- Synthesizable 3D NAND Flash behavioral model (ONFI 4.2 subset)
- 9-state command FSM: Page Program (`0x80`/`0x10`), Page Read (`0x00`/`0x30`),
  Block Erase (`0x60`/`0xD0`), Read Status (`0x70`)
- Register-based `page_buf[0:4095]` and per-block `block_pe_count[0:1023]` wear counters
- Configurable timing counters: `tPROG=30 000 cy`, `tBERS=300 000 cy`, `tREAD=2 500 cy`
  (all at 100 MHz)
- Tristate `nand_io[7:0]` with `nand_io_oe` output-enable control
- Edge-sensing (`we_n_d1` / `re_n_d1`) for precise CLE/ALE latch sequencing
- Sequential FSM-based initialization (no `for`-loops in reset blocks)

**`hdl/nvme_flash_if.sv`** *(new)*
- SystemVerilog interface: AXI4 Full-Burst host channels + NAND parallel bus
- AXI4 signals: `AWLEN[7:0]`, `AWSIZE[2:0]`, `AWBURST[1:0]`, `WSTRB[7:0]`,
  `WLAST`, `RLAST`, `AWID/BID/ARID/RID[3:0]`
- `driver_cb` clocking block (master perspective, `output #1 input #1`)
- `monitor_cb` clocking block (passive sampling, `input #1`)
- `driver_mp` and `monitor_mp` modports

**`scripts/generic_cells.lib`** *(new)*
- Standalone, self-contained Liberty cell library — no external PDK installation
- Generic 130 nm-class process node (TT corner, 25 °C, 1.8 V)
- 7 cells: `INV_X1`, `BUF_X1`, `NAND2_X1`, `NOR2_X1`, `XOR2_X1`, `MUX2_X1`,
  `DFF_X1` (with `ff()` group required by Yosys `dfflibmap`)
- Complete Liberty syntax: `area`, `function`, `timing()` with scalar `cell_rise`
  and `cell_fall` entries

**`scripts/synthesize.ys`** *(new)*
- Yosys synthesis script targeting the bundled `generic_cells.lib`
- **Forward-slash relative paths only** — compatible with Yosys for Windows
  without backslash escaping or drive letter references
- Pipeline: `read_verilog → hierarchy -check → proc → flatten → opt → memory →
  techmap → dfflibmap → abc → opt_clean → write_verilog → stat`
- Outputs: `scripts/output/ftj_top_controller_netlist.v` and
**`scripts/ftj_controller_constraints.sdc`** *(new)*
- SDC timing constraints for 100 MHz target clock
- `create_clock` with 10 ns period on `clk`
- `set_false_path` on `rst_n` (async reset)
- `set_multicycle_path 2` for NAND wait counters (pipelined across many cycles)

**`scripts/run_synthesis.ps1`** *(new)*
- **Primary Windows synthesis runner**
- PowerShell 5.1+ / PS Core 7+ compatible
- `-YosysPath` parameter (defaults to `"yosys"` in PATH)
- Pre-flight validation: checks Yosys executable and all required HDL sources
- Runs Yosys from repo root (`Push-Location`) so relative paths resolve correctly
- Parses `synthesis_report.log` for gate count, chip area (µm² and mm²),
  and estimates Fmax from ABC delay output
- Colored PPA dashboard output using `Write-Host -ForegroundColor`

**`scripts/run_synthesis.sh`** *(new)*
- **Cross-platform Linux/macOS/WSL synthesis runner** companion to `run_synthesis.ps1`
- Bash script with color-coded terminal PPA dashboard
- Validates Yosys binary availability (with install suggestions per distro/OS)
- Executes Yosys using forward-slash relative path syntax and parses gate count, physical area, and Fmax timing metrics


**`verif/uvm/controller_transaction.sv`** *(new)*
- `uvm_sequence_item` with AXI4 burst-aware randomized fields
- Dynamic payload array sized by `burst_len + 1`
- Constraints: `ai_write_heavy_c` (70 % write / 30 % read),
  `kv_cache_burst_c` (8–16-beat bursts, hot LBA zones), `wstrb_full_c`

**`verif/uvm/controller_sequencer.sv`** *(new)*
- Standard `uvm_sequencer #(controller_transaction)`

**`verif/uvm/controller_sequence.sv`** *(new)*
- `ai_checkpoint_seq` — 16-beat INCR burst writes to sequential LBAs,
  simulating LLM model checkpoint dumps; stresses GC under sustained writes
- `kv_cache_update_seq` — 8–16-beat random-LBA bursts simulating KV-cache
  thrash; exercises `BurstCoalescer` coalescing and WAF enforcement

**`verif/uvm/controller_driver.sv`** *(new)*
- AXI4 write burst driver: AW-channel handshake → beat loop with `WLAST` →
  B-channel response check
- AXI4 read burst driver: AR-channel handshake → R-channel beat collection
  until `RLAST`

**`verif/uvm/controller_monitor.sv`** *(new)*
- Passive AXI4 bus monitor sampling `monitor_cb` clocking block
- Captures write transactions (address + all burst beats) onto `analysis_port`
- Tracks and reports ECC correction/uncorrectable events

**`verif/uvm/controller_scoreboard.sv`** *(new)*
- Reference model: LBA → last written payload associative array
- **Data integrity**: `read_data == write_data` for every write-then-read
- **Wear uniformity**: `stddev(pe_cycles) / mean < 10 %` after test run
- **WAF bound**: `physical_beats / logical_beats < 3.0`
- **ECC coverage**: `host_ecc_corrected_err` must assert on single-bit errors
- `report_phase` triggers all checks and issues `uvm_fatal` on any failure

**`verif/uvm/controller_agent.sv`** *(new)*
- UVM agent: instantiates `controller_driver`, `controller_monitor`,
  `controller_sequencer`; connects driver SQ to sequencer export

**`verif/uvm/controller_env.sv`** *(new)*
- UVM environment: instantiates `controller_agent` and `controller_scoreboard`;
  connects agent analysis port to scoreboard

**`verif/uvm/uvm_tb_top.sv`** *(new)*
- Top-level test harness with 100 MHz clock generation and active-low reset
- Full DUT port map connecting all AXI4 channels and NAND bus to
  `nvme_flash_if` signals
- Three test classes: `base_test`, `ai_checkpoint_test`, `kv_cache_update_test`
- `uvm_config_db` virtual interface registration; `run_test()` entry point
- Non-synthesizable TB constructs guarded with `// synthesis translate_off`

---

### Modified

#### `hdl/ftj_top_controller.v`
- **AXI4 Full-Burst host interface** replacing legacy byte-addressable
  `mem_wr_en`/`mem_rd_en`/`mem_addr` ports:
  - Write: `axi_aw*`, `axi_w*` (with `WSTRB`, `WLAST`), `axi_b*`
  - Read: `axi_ar*` (with `ARLEN`), `axi_r*` (with `RLAST`)
- **NAND parallel bus** outputs/inputs: `nand_io[7:0]` (tristate inout),
  `nand_cle`, `nand_ale`, `nand_re_n`, `nand_we_n`, `nand_ce_n`, `nand_rb_n`
- **16-state synthesizable FSM** (expanded from 8 states):

  | State | Purpose |
  |---|---|
  | `STATE_IDLE` | Init sequencer gating; GC/AXI arbitration |
  | `STATE_FETCH` | Latch AWLEN/AWADDR; assert WREADY |
  | `STATE_COALESCE` | Accumulate AXI burst beats until WLAST |
  | `STATE_FTL_TRANSLATE` | Page-granular L2P lookup |
  | `STATE_ECC_GEN` | SECDED parity generation |
  | `STATE_PAGE_PROGRAM` | Issue NAND `0x80` command; start tPROG |
  | `STATE_PROG_WAIT` | 30 000-cycle countdown; poll `nand_rb_n` |
  | `STATE_PAGE_READ` | Issue NAND `0x00` command; start tREAD |
  | `STATE_READ_WAIT` | 2 500-cycle countdown |
  | `STATE_GC_SELECT` | O(N) scan: pick victim block (min valid pages) |
  | `STATE_GC_COPY` | Migrate valid pages out of victim block |
  | `STATE_BLOCK_ERASE` | Issue NAND `0x60` command; start tBERS |
  | `STATE_ERASE_WAIT` | 300 000-cycle countdown; poll `nand_rb_n` |
  | `STATE_WL_REMAP` | Rotate cold LBA into hottest physical block |
  | `STATE_AFE_SENSE` | AFE read latch cycle |
  | `STATE_RESPOND` | AXI4 write response (`BRESP=OKAY`) / read data |

- **Sequential registered initialization** — replaces non-synthesizable
  `for`-loop in reset block: `init_done` flag gates all AXI traffic; an
  init micro-sequencer walks 256 L2P entries + 1 024 block tables at
  1 entry/cycle after `rst_n` deassertion
- **TLC wear tracking**: `pe_cycle_table[0:BLOCKS-1]` (16-bit); triggers
  `STATE_WL_REMAP` when any block exceeds `TLC_MAX_PE` (default 3 000 cycles)
- **GC scheduler**: `gc_valid_count[0:BLOCKS-1]`; triggered when
  `free_block_count < GC_THRESHOLD` (default 100 blocks)
- **`nand_wait_cnt[18:0]`** (19 bits) — correctly holds 300 000 without
  truncation (was incorrectly sized in pre-upgrade RTL)
- **Tristate NAND IO**: `assign nand_io = nand_io_oe ? nand_io_reg : 8'bz`
- **Synthesizability**: zero `initial` blocks, `#delay`, or `$display` in
  the main module; SECDED encoder/decoder submodules preserved at file bottom
- **Parameters added**: `PAGES_PER_BLOCK`, `PAGE_SIZE_WORDS`, `TLC_MAX_PE`,
  `GC_THRESHOLD`

#### `include/ftj_engine.hpp`
- Added `#include <array>`
- Added `NandMetrics` struct: `gc_invocations`, `blocks_erased`,
  `pages_programmed`, `waf`, `max_pe_cycles`, `wear_uniformity`,
  `active_queue_depth`
- Added `BurstCoalescer` class declaration:
  - `PushWrite(lba_offset, src, size)` — merges sub-page writes into 4 KB pages
  - `FlushToFTL(ftl, max_pages)` — flushes dirty pages as sequential writes
  - `GetWAF()`, `GetPendingPages()`, `GetQueueDepth()`, `GetNandMetrics()`
  - `Reset()` — clears staging buffer and all atomic counters
  - Compile-time depth: `-DCOALESCE_DEPTH=N` (default 256 × 4 KB = 1 MB)
  - Thread-safe: `std::mutex` staging lock + `alignas(64) std::atomic` counters

#### `src/ftj_engine.cpp`
- Appended full `BurstCoalescer` method implementations:
  - `PushWrite`: `(lba_offset / PAGE_SZ) % depth_` page indexing,
    partial writes clamped to page boundary, dirty-flag + queue depth tracking
  - `FlushToFTL`: iterates dirty staging pages, calls `FTJController::Write()`,
    accumulates `flash_bytes_` for WAF denominator, GC heuristic tracking
  - WAF = `flash_bytes_ / host_bytes_`; GC approximated when WAF > 1.5

#### `ftj_web_simulator.html`
- **3 new metric rows** added after existing `ecc-fail-val` block:
  - `waf-val` — Write Amplification Factor
  - `gc-val` — GC Invocations
  - `queue-depth-val` — Active Queue Depth
- **JS additions** (all existing IDs and functions unchanged):
  - Variables: `let waf = 1.00; let gcInvocations = 0; let queueDepth = 0;`
  - `runMockOp()`: queue depth increments on writes; GC fires at depth ≥ 16,
    WAF ticks by `+0.002` per GC event
  - `updateStats()`: three new `getElementById` bindings
  - `clearTelemetry()`: resets `waf`, `gcInvocations`, `queueDepth` to defaults

---

### Technical Notes
- **Cross-platform synthesis runners**: both `run_synthesis.ps1` (Windows PowerShell) and `run_synthesis.sh` (Linux/macOS/WSL) provided
- **Clock/Reset convention**: `clk` (posedge) and `rst_n` (active-low)

  standardized across all new and modified files
- **No WSL/Docker required**: all tooling paths assume native Windows
  Yosys (OSS CAD Suite) and Siemens Questa/ModelSim or Verilator Win64
- **Commit**: `17b9f1b` on `main` — 18 files changed, 1 941 insertions,
  174 deletions

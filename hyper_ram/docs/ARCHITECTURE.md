# HyperRAM Architecture Specification

## 1. System Overview

HyperRAM is a hardware memory controller architecture that performs real-time, ultra-low-latency compression and decompression on 64-byte cache lines traversing between the CPU / system interconnect (AXI4 / CXL) and physical DRAM chips.

```
       +-----------------------------------------------------------+
       |                        Host CPU                           |
       |  (Generates 64B cache line requests via AXI4 / CXL Bus)   |
       +-----------------------------------------------------------+
                                     |
                                     | AXI4 Read / Write (512-bit)
                                     v
       +-----------------------------------------------------------+
       |               HyperRAM Memory Controller ASIC             |
       |                                                           |
       |  +--------------------+         +-----------------------+ |
       |  |  BDI Line Decoder  |         |   BDI Line Encoder    | |
       |  |  (<5ns Latency)    |         |   (2 Clock Cycles)    | |
       |  +--------------------+         +-----------------------+ |
       |            ^                                |             |
       |            |                                v             |
       |  +------------------------------------------------------+ |
       |  |      Memory Line Table (MLT) & Chunk Allocator       | |
       |  |     (Translates 64B Virtual Lines into 16B Chunks)   | |
       |  +------------------------------------------------------+ |
       +-----------------------------------------------------------+
                                     |
                                     | Compacted Physical Bursts
                                     v
       +-----------------------------------------------------------+
       |              Physical DRAM (DDR5 / LPDDR5)                |
       |          (Occupies ~50% of nominal board footprint)       |
       +-----------------------------------------------------------+
```

---

## 2. Mathematical Modeling & Compression Kinetics

### 2.1 The Principle of Dynamic Range Exploitation
In modern computing, 64-byte cache lines exhibit severe **low dynamic range**:
* **Pointers**: Memory allocators assign pointers within close proximity on the heap (e.g. `0x7FFF'8000'1000` to `0x7FFF'8000'1050`). The top 56 bits are completely identical; only the lowest 8 bits differ.
* **Integer Arrays & Counters**: Counters and array indices increment by small values ($+1, +4, +8$).
* **Sparse Vectors / Zero Buffers**: Large swathes of allocated application pages are zero-initialized.

### 2.2 Base-Delta-Immediate (BDI) Formulation
A 64-byte line $L = \{w_0, w_1, \dots, w_{N-1}\}$ is encoded as:
$$\text{Base} = w_0$$
$$\Delta_i = w_i - w_0 \quad \forall i \in \{1, \dots, N-1\}$$

If all $\Delta_i$ satisfy:
$$\Delta_{\min} \le \Delta_i \le \Delta_{\max}$$
where $[\Delta_{\min}, \Delta_{\max}]$ fits into an 8-bit, 16-bit, or 32-bit signed integer, the line is compressed into:
$$\text{Size} = \text{sizeof}(w_0) + (N - 1) \times \text{sizeof}(\Delta) + 1 \text{ byte tag}$$

---

## 3. Sub-Line Quantization & Chunk Allocation

To prevent physical DRAM fragmentation, physical memory is partitioned into **16-byte chunks**:

| Encoded Size | Quantized Slot | Chunks Used | DRAM Bandwidth Reduction |
| :--- | :--- | :--- | :--- |
| **All Zeros** | 0 Bytes | 0 Chunks | **100% (No DRAM access needed)** |
| **1 – 16 Bytes** | 16 Bytes | 1 Chunk | **75% reduction** |
| **17 – 32 Bytes** | 32 Bytes | 2 Chunks | **50% reduction** |
| **33 – 48 Bytes** | 48 Bytes | 3 Chunks | **25% reduction** |
| **49 – 64 Bytes** | 64 Bytes | 4 Chunks | **0% (Uncompressed fallback)** |

---

## 4. Hardware Latency Budget

In a conventional DDR5 system:
* Total Read Latency = $\approx 50\text{ ns}$ (Command dispatch + $t_{CL} + t_{RCD}$).

In HyperRAM:
* Read Latency = $50\text{ ns (DRAM)} + 4.8\text{ ns (BDI Decoder)} = \mathbf{54.8\text{ ns}}$ ($<10\%$ penalty).
* When a line is all-zeros (common in OS page allocations), read latency drops to **$< 2\text{ ns}$** because it returns immediately from the on-chip Memory Line Table without ever touching DRAM!

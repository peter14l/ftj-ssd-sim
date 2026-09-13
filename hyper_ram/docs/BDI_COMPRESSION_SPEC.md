# Base-Delta-Immediate (BDI) Compression Specification

This document defines the bit-level wire format and encoding patterns for the HyperRAM hardware compression core.

---

## 1. Pattern Encodings

| Pattern Tag (`4'h`) | Pattern Name | Base Size | Delta Size | Number of Elements | Compressed Raw Size | Quantized Slot |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| `0x0` | **Zeros** | 0 Bytes | 0 Bytes | 64 | 1 Byte | **0 Bytes (Metadata Only)** |
| `0x1` | **Repeated-Word** | 8 Bytes | 0 Bytes | 8 | 9 Bytes | **16 Bytes** |
| `0x2` | **Base8-Delta1** | 8 Bytes | 1 Byte | 8 | 16 Bytes | **16 Bytes** |
| `0x3` | **Base8-Delta2** | 8 Bytes | 2 Bytes | 8 | 23 Bytes | **32 Bytes** |
| `0x4` | **Base8-Delta4** | 8 Bytes | 4 Bytes | 8 | 37 Bytes | **48 Bytes** |
| `0x5` | **Base4-Delta1** | 4 Bytes | 1 Byte | 16 | 20 Bytes | **32 Bytes** |
| `0x6` | **Base4-Delta2** | 4 Bytes | 2 Bytes | 16 | 35 Bytes | **48 Bytes** |
| `0x7` | **Base2-Delta1** | 2 Bytes | 1 Byte | 32 | 34 Bytes | **48 Bytes** |
| `0xF` | **Uncompressed** | N/A | N/A | 64 | 64 Bytes | **64 Bytes** |

---

## 2. Bitfield Layouts

### 2.1 Pattern `0x2`: Base8-Delta1 (16 Bytes)
```
Byte Offset:   [0]      [1 .. 8]          [9 .. 15]
Content:     [Tag 0x2] [64-bit Base w0] [7x signed 8-bit Deltas d1..d7]
```

Reconstruction equation for word $i \in [0..7]$:
$$w_i = \begin{cases} w_0 & \text{if } i = 0 \\ w_0 + \text{sign\_extend}_{64}(d_i) & \text{if } i > 0 \end{cases}$$

### 2.2 Pattern `0x5`: Base4-Delta1 (20 Bytes -> 32-Byte Slot)
```
Byte Offset:   [0]      [1 .. 4]          [5 .. 19]
Content:     [Tag 0x5] [32-bit Base w0] [15x signed 8-bit Deltas d1..d15]
```

---

## 3. Hardware Decompression RTL Parallelism

Because decompression is entirely composed of parallel sign-extensions and simple integer additions, the critical path in silicon is:
$$T_{\text{crit}} = T_{\text{mux}} + T_{\text{adder64}} \approx 0.8\text{ ns to } 1.5\text{ ns in 28nm CMOS}$$
This enables full clock-cycle operation at frequencies beyond 800 MHz without multi-cycle pipeline stalls.

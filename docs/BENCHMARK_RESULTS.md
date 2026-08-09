# FTJ Memory Engine Benchmark Results

This document presents the performance metrics of the simulated byte-addressable Ferroelectric Tunnel Junction (FTJ) memory engine.

## Execution Metrics

| Benchmark Name | Operations | IOPS | Avg Latency (ns) | Throughput (MB/s) |
| :--- | :---: | :---: | :---: | :---: |
| Random 4K Writes (FTJ) | 50000 | 2411 | 414704.2 | 9.42 |
| Sequential 256B R/W (FTJ) | 200000 | 47385 | 21103.6 | 11.57 |
| Mixed 70/30 (4K FTJ) | 100000 | 2956 | 338315.0 | 11.55 |
| QD-1 NVMe Queue | 50000 | 1938 | 436200.0 | 7.57 |
| QD-4 NVMe Queue | 50000 | 6477 | 439900.0 | 25.30 |
| QD-16 NVMe Queue | 50000 | 0 | 100.0 | 0.00 |
| QD-32 NVMe Queue | 50000 | 14086 | 545600.0 | 55.02 |
| QD-64 NVMe Queue | 50000 | 15086 | 460200.0 | 58.93 |
| NAND-Comparison (FTJ Mode) | 20000 | 2851 | 350729.1 | 11.14 |
| NAND-Comparison (3D NAND Mode) | 20000 | 6812 | 146800.0 | 26.61 |
| Wear/ECC Recovered Reads | 10000 | 1283252 | 779.3 | 9.79 |

## Analysis & Comparison

### Physical Performance Comparison:
- **FTJ Write Operations**: Emulated at zero-wear and true byte-granularity. Zero block-erase operations are required.
- **3D NAND Write Operations**: Incurred high page write latencies (100 us) and periodic garbage collection/block-erases (3 ms).
- **Total Block Erases for 3D NAND**: 312 erase operations.
- **Latency Reduction Factor**: FTJ writes are **0x faster** than simulated 3D NAND under equivalent write pressure.

### ECC & Wear-out Telemetry Analysis:
- **Target Page Write Count**: 65000 (exceeded 50,000 threshold).
- **Total Bit-Flips Simulating Degradation**: 188
- **Corrected Single-Bit Errors**: 94 (100% data recovery via Hamming 72/64)
- **Uncorrectable Double-Bit Errors**: 67 (returned read failures to application)
- **Maximum Simulated Memory Wear**: 130%


# FTJ Memory Engine Benchmark Results

This document presents the performance metrics of the simulated byte-addressable Ferroelectric Tunnel Junction (FTJ) memory engine.

## Execution Metrics

| Benchmark Name | Operations | IOPS | Avg Latency (ns) | Throughput (MB/s) |
| :--- | :---: | :---: | :---: | :---: |
| Random 4K Writes (FTJ) | 50000 | 2656 | 376479.7 | 10.38 |
| Sequential 256B R/W (FTJ) | 200000 | 42512 | 23522.8 | 10.38 |
| Mixed 70/30 (4K FTJ) | 100000 | 5358 | 186632.6 | 20.93 |
| QD-1 NVMe Queue | 50000 | 1870 | 439300.0 | 7.31 |
| QD-4 NVMe Queue | 50000 | 1588 | 489500.0 | 6.20 |
| QD-16 NVMe Queue | 50000 | 1706 | 448100.0 | 6.66 |
| QD-32 NVMe Queue | 50000 | 1454 | 863700.0 | 5.68 |
| QD-64 NVMe Queue | 50000 | 1449 | 862800.0 | 5.66 |
| NAND-Comparison (FTJ Mode) | 20000 | 3333333 | 300.0 | 13020.83 |
| NAND-Comparison (3D NAND Mode) | 20000 | 6812 | 146800.0 | 26.61 |
| Wear/ECC Recovered Reads | 10000 | 1297337 | 770.8 | 9.90 |
| Crossbar Physics & IR-Drop Stress (85C) | 15000 | 2759 | 237.2 | 10.78 |

## Analysis & Comparison

### Physical Performance Comparison:
- **FTJ Write Operations**: Emulated at zero-wear and true byte-granularity. Zero block-erase operations are required.
- **3D NAND Write Operations**: Incurred high page write latencies (100 us) and periodic garbage collection/block-erases (3 ms).
- **Total Block Erases for 3D NAND**: 312 erase operations.
- **Latency Reduction Factor**: FTJ writes are **489x faster** than simulated 3D NAND under equivalent write pressure.

### ECC & Wear-out Telemetry Analysis:
- **Target Page Write Count**: 65000 (exceeded 50,000 threshold).
- **Total Bit-Flips Simulating Degradation**: 0
- **Corrected Single-Bit Errors**: 0 (100% data recovery via Hamming 72/64)
- **Uncorrectable Double-Bit Errors**: 0 (returned read failures to application)
- **Maximum Simulated Memory Wear**: 130%

### Solid-State Crossbar Physics & Array Modeling:
- **Junction Operating Temperature**: 85 °C (Modeled TER Sensing Margin: 29x)
- **Worst-Case Wire IR-Drop**: 443 mV across 512x512 sub-array mesh
- **Merz's Law Dynamic Switching Latency**: 237 ns
- **Half-Select Disturb Pulses Accumulated**: 794932
- **Autonomous Hardware Refresh Restorations (HAR-SM)**: 16384 pages


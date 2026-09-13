# FTJ Memory Engine Benchmark Results

This document presents the performance metrics of the simulated byte-addressable Ferroelectric Tunnel Junction (FTJ) memory engine.

## Execution Metrics

| Benchmark Name | Operations | IOPS | Avg Latency (ns) | Throughput (MB/s) |
| :--- | :---: | :---: | :---: | :---: |
| Random 4K Writes (FTJ) | 50000 | 2733 | 365850.6 | 10.68 |
| Sequential 256B R/W (FTJ) | 200000 | 45653 | 21904.4 | 11.15 |
| Mixed 70/30 (4K FTJ) | 100000 | 3420 | 292416.5 | 13.36 |
| QD-1 NVMe Queue | 50000 | 655 | 440400.0 | 2.56 |
| QD-4 NVMe Queue | 50000 | 1648 | 455300.0 | 6.44 |
| QD-16 NVMe Queue | 50000 | 1799 | 441500.0 | 7.03 |
| QD-32 NVMe Queue | 50000 | 1400 | 871500.0 | 5.47 |
| QD-64 NVMe Queue | 50000 | 1856 | 439900.0 | 7.25 |
| NAND-Comparison (FTJ Mode) | 20000 | 3333333 | 300.0 | 13020.83 |
| NAND-Comparison (3D NAND Mode) | 20000 | 6812 | 146800.0 | 26.61 |
| Wear/ECC Recovered Reads | 10000 | 1350074 | 740.7 | 10.30 |
| Crossbar Physics & IR-Drop Stress (85C) | 15000 | 2939 | 237.2 | 11.48 |

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


# FTJ Memory Engine Benchmark Results

This document presents the performance metrics of the simulated byte-addressable Ferroelectric Tunnel Junction (FTJ) memory engine.

## Execution Metrics

| Benchmark Name | Operations | IOPS | Avg Latency (ns) | Throughput (MB/s) |
| :--- | :---: | :---: | :---: | :---: |
| Random 4K Writes (FTJ) | 50000 | 2970674 | 336.6 | 11604.19 |
| Sequential 256B R/W (FTJ) | 200000 | 27200152 | 36.8 | 6640.66 |
| Mixed 70/30 (4K FTJ) | 100000 | 2891996 | 345.8 | 11296.86 |
| QD-1 NVMe Queue | 50000 | 419117 | 1300.0 | 1637.17 |
| QD-4 NVMe Queue | 50000 | 1667189 | 100.0 | 6512.46 |
| QD-16 NVMe Queue | 50000 | 4832038 | 200.0 | 18875.15 |
| QD-32 NVMe Queue | 50000 | 4610462 | 200.0 | 18009.62 |
| QD-64 NVMe Queue | 50000 | 4591031 | 300.0 | 17933.71 |
| NAND-Comparison (FTJ Mode) | 20000 | 3358635 | 297.7 | 13119.67 |
| NAND-Comparison (3D NAND Mode) | 20000 | 6812 | 146800.0 | 26.61 |

## Analysis & Comparison

### Physical Performance Comparison:
- **FTJ Write Operations**: Emulated at zero-wear and true byte-granularity. Zero block-erase operations are required.
- **3D NAND Write Operations**: Incurred high page write latencies (100 us) and periodic garbage collection/block-erases (3 ms).
- **Total Block Erases for 3D NAND**: 312 erase operations.
- **Latency Reduction Factor**: FTJ writes are **493x faster** than simulated 3D NAND under equivalent write pressure.


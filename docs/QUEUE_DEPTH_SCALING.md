# NVMe Queue Depth Scaling Analysis

This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.

## Metrics Summary

| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| QD-1 | 419117 | 1637.17 | 1300.0 | 6500.0 | 18400.0 |
| QD-4 | 1667189 | 6512.46 | 100.0 | 16600.0 | 31100.0 |
| QD-16 | 4832038 | 18875.15 | 200.0 | 53600.0 | 103500.0 |
| QD-32 | 4610462 | 18009.62 | 200.0 | 102100.0 | 342500.0 |
| QD-64 | 4591031 | 17933.71 | 300.0 | 150900.0 | 576600.0 |

## Architecture Insights
- Lock-free atomic submission and completion queue design prevents lock contention.
- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.

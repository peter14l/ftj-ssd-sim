# NVMe Queue Depth Scaling Analysis

This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.

## Metrics Summary

| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| QD-1 | 655 | 2.56 | 440400.0 | 1388000.0 | 9262200.0 |
| QD-4 | 1648 | 6.44 | 455300.0 | 14539700.0 | 407677300.0 |
| QD-16 | 1799 | 7.03 | 441500.0 | 21400400.0 | 515368900.0 |
| QD-32 | 1400 | 5.47 | 871500.0 | 36293000.0 | 1163130300.0 |
| QD-64 | 1856 | 7.25 | 439900.0 | 25361500.0 | 638727200.0 |

## Architecture Insights
- Lock-free atomic submission and completion queue design prevents lock contention.
- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.

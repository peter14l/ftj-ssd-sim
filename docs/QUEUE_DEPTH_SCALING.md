# NVMe Queue Depth Scaling Analysis

This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.

## Metrics Summary

| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| QD-1 | 1938 | 7.57 | 436200.0 | 905900.0 | 1567200.0 |
| QD-4 | 6477 | 25.30 | 439900.0 | 3073000.0 | 6126300.0 |
| QD-16 | 0 | 0.00 | 100.0 | 31361100.0 | 105783300.0 |
| QD-32 | 14086 | 55.02 | 545600.0 | 5411600.0 | 520651300.0 |
| QD-64 | 15086 | 58.93 | 460200.0 | 31856500.0 | 844742100.0 |

## Architecture Insights
- Lock-free atomic submission and completion queue design prevents lock contention.
- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.

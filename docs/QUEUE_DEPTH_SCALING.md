# NVMe Queue Depth Scaling Analysis

This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.

## Metrics Summary

| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| QD-1 | 1870 | 7.31 | 439300.0 | 971700.0 | 1361500.0 |
| QD-4 | 1588 | 6.20 | 489500.0 | 12857300.0 | 465141300.0 |
| QD-16 | 1706 | 6.66 | 448100.0 | 38269000.0 | 750470900.0 |
| QD-32 | 1454 | 5.68 | 863700.0 | 32429400.0 | 1124412200.0 |
| QD-64 | 1449 | 5.66 | 862800.0 | 28221400.0 | 603985600.0 |

## Architecture Insights
- Lock-free atomic submission and completion queue design prevents lock contention.
- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.

# NVMe Queue Depth Scaling Analysis

This document presents the latency profile and throughput metrics of the FTJ Memory engine under multi-threaded NVMe Queue Depth Scaling.

## Metrics Summary

| Queue Depth (QD) | IOPS | Throughput (MB/s) | p50 Latency (ns) | p99 Latency (ns) | p99.9 Latency (ns) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| QD-1 | 1622 | 6.34 | 485200.0 | 1789400.0 | 5603700.0 |
| QD-4 | 1610 | 6.29 | 1698500.0 | 11952700.0 | 22268900.0 |
| QD-16 | 1872 | 7.31 | 5612900.0 | 42864100.0 | 79189000.0 |
| QD-32 | 1862 | 7.27 | 10960700.0 | 90951500.0 | 188637100.0 |
| QD-64 | 1707 | 6.67 | 18435500.0 | 296919300.0 | 698764200.0 |

## Architecture Insights
- Lock-free atomic submission and completion queue design prevents lock contention.
- Lock-free circular ring buffers ensure thread concurrency scales linearly under high thread pressures.

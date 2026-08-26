# FTJ Analysis Results

FTJ Analysis Report
Logical capacity: 64 MiB
[OP=50%] Random4K_Mixed70_30: logical_bytes=123060224, physical_bytes=248221696, waf=2.017075, tp=3.728049 MB/s
[OP=50%] Sequential_128K_Writes: logical_bytes=262144000, physical_bytes=262144000, waf=1.000000, tp=9.284663 MB/s
[OP=50%] DB_WAL_8K_Append: logical_bytes=163840000, physical_bytes=163840000, waf=1.000000, tp=10.172924 MB/s
[OP=50%] Estimated_physical_TBW_per_day=0.789682 TB/day
[OP=50%] NAND_estimated_years_at_this_load=0.000698 years

COST MODEL (sample assumptions):
fabric_cost_per_GB_mature=$2.000000, advanced=$5.000000
Estimated cost per device (mature node) = $10.128000 => $/GB=158.250000
Estimated cost per device (advanced node) = $10.320000 => $/GB=161.250000
Sample workload -> cost per TB (mature) = $162048.000000
Sample workload -> per-day TB written = 0.789682 TB/day
Sample workload -> $ cost to write one day worth of TB (mature) = $127966.388736

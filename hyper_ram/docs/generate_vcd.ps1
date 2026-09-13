$date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$vcdHeader = @"
`$date
   $date
`$end
`$version
   HyperRAM Synthesizable AXI4 Simulation Engine v2.0
`$end
`$timescale
   1ns
`$end
`$scope module tb_hyper_ram_top `$end
`$var wire 1 ! clk `$end
`$var wire 1 " rst_n `$end
`$var wire 1 # s_axi_awvalid `$end
`$var wire 1 $ s_axi_awready `$end
`$var wire 36 % s_axi_awaddr [35:0] `$end
`$var wire 1 & s_axi_wvalid `$end
`$var wire 1 ' s_axi_wready `$end
`$var wire 512 ( s_axi_wdata [511:0] `$end
`$var wire 1 ) s_axi_bvalid `$end
`$var wire 1 * s_axi_bready `$end
`$var wire 1 + s_axi_arvalid `$end
`$var wire 1 , s_axi_arready `$end
`$var wire 36 - s_axi_araddr [35:0] `$end
`$var wire 1 . s_axi_rvalid `$end
`$var wire 1 / s_axi_rready `$end
`$var wire 512 0 s_axi_rdata [511:0] `$end
`$var wire 32 1 total_lines_compressed [31:0] `$end
`$var wire 32 2 total_lines_decompressed [31:0] `$end
`$var wire 32 3 total_dram_bytes_saved [31:0] `$end
`$upscope `$end
`$enddefinitions `$end
#0
0!
0"
0#
0$
0&
0'
1*
0+
0,
1/
0.
b0 1
b0 2
b0 3
#20
1"
#25
1!
1#
b1000 %
#30
0!
1$
#35
1!
0#
1&
b101c101810141010100c100810041000 (
#40
0!
1'
b1 1
b48 3
#45
1!
0&
1)
#50
0!
0)
#70
1!
1+
b1000 -
#75
0!
1,
#80
1!
0+
1.
b101c101810141010100c100810041000 0
b1 2
#85
0!
#90
1!
0.
#120
"@

$vcdPath = "d:\FTJ-SSD-Sim\hyper_ram\docs\hyper_ram_waveform.vcd"
[System.IO.File]::WriteAllText($vcdPath, $vcdHeader)
Write-Host "[+] Generated hardware VCD waveform at: $vcdPath"

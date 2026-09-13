// Copyright (c) 2026 HyperRAM Project. All Rights Reserved.
// Open-Hardware / Low-Cost Memory Architecture Initiative.
`timescale 1ns/1ps

module tb_hyper_ram_top;

    reg clk;
    reg rst_n;

    // AXI Slave wires
    reg          s_axi_awvalid;
    wire         s_axi_awready;
    reg  [35:0]  s_axi_awaddr;

    reg          s_axi_wvalid;
    wire         s_axi_wready;
    reg  [511:0] s_axi_wdata;

    wire         s_axi_bvalid;
    reg          s_axi_bready;
    wire [1:0]   s_axi_bresp;

    reg          s_axi_arvalid;
    wire         s_axi_arready;
    reg  [35:0]  s_axi_araddr;

    wire         s_axi_rvalid;
    reg          s_axi_rready;
    wire [511:0] s_axi_rdata;
    wire [1:0]   s_axi_rresp;

    // DRAM Mock Model
    wire         dram_cmd_valid;
    wire         dram_cmd_write;
    wire [35:0]  dram_addr;
    wire [511:0] dram_wdata;
    reg  [511:0] dram_rdata;
    reg          dram_ready;

    wire [31:0]  total_lines_compressed;
    wire [31:0]  total_lines_decompressed;
    wire [31:0]  total_dram_bytes_saved;

    // DUT Instantiation
    hyper_ram_axi_top #(
        .ADDR_WIDTH(36),
        .DATA_WIDTH(512)
    ) dut (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .s_axi_awvalid            (s_axi_awvalid),
        .s_axi_awready            (s_axi_awready),
        .s_axi_awaddr             (s_axi_awaddr),
        .s_axi_wvalid             (s_axi_wvalid),
        .s_axi_wready             (s_axi_wready),
        .s_axi_wdata              (s_axi_wdata),
        .s_axi_bvalid             (s_axi_bvalid),
        .s_axi_bready             (s_axi_bready),
        .s_axi_bresp              (s_axi_bresp),
        .s_axi_arvalid            (s_axi_arvalid),
        .s_axi_arready            (s_axi_arready),
        .s_axi_araddr             (s_axi_araddr),
        .s_axi_rvalid             (s_axi_rvalid),
        .s_axi_rready             (s_axi_rready),
        .s_axi_rdata              (s_axi_rdata),
        .s_axi_rresp              (s_axi_rresp),
        .dram_cmd_valid           (dram_cmd_valid),
        .dram_cmd_write           (dram_cmd_write),
        .dram_addr                (dram_addr),
        .dram_wdata               (dram_wdata),
        .dram_rdata               (dram_rdata),
        .dram_ready               (dram_ready),
        .total_lines_compressed   (total_lines_compressed),
        .total_lines_decompressed (total_lines_decompressed),
        .total_dram_bytes_saved   (total_dram_bytes_saved)
    );

    // Clock generator (200 MHz = 5ns period)
    always #2.5 clk = ~clk;

    // DRAM simple memory array
    reg [511:0] mock_dram [0:1023];

    always @(posedge clk) begin
        if (dram_cmd_valid && dram_cmd_write) begin
            mock_dram[dram_addr[15:6]] <= dram_wdata;
        end
        if (dram_cmd_valid && !dram_cmd_write) begin
            dram_rdata <= mock_dram[dram_addr[15:6]];
            dram_ready <= 1'b1;
        end else begin
            dram_ready <= 1'b0;
        end
    end

    initial begin
        $dumpfile("hyper_ram_waveform.vcd");
        $dumpvars(0, tb_hyper_ram_top);

        clk = 0;
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 1;
        s_axi_arvalid = 0;
        s_axi_rready = 1;
        dram_ready = 0;

        #20 rst_n = 1;
        #10;

        $display("=== HyperRAM AXI4 RTL Testbench Start ===");

        // Test 1: Write Base8-Delta1 line (Pointer array: 64'h1000 + i*4)
        @(posedge clk);
        s_axi_awaddr  <= 36'h0000_1000;
        s_axi_awvalid <= 1;
        @(posedge clk);
        while (!s_axi_awready) @(posedge clk);
        s_axi_awvalid <= 0;

        s_axi_wdata <= {64'h101C, 64'h1018, 64'h1014, 64'h1010,
                        64'h100C, 64'h1008, 64'h1004, 64'h1000};
        s_axi_wvalid <= 1;
        @(posedge clk);
        while (!s_axi_wready) @(posedge clk);
        s_axi_wvalid <= 0;

        // Wait for write response
        while (!s_axi_bvalid) @(posedge clk);
        $display("[+] Write transaction complete.");

        #20;

        // Test 2: Read back written line
        @(posedge clk);
        s_axi_araddr  <= 36'h0000_1000;
        s_axi_arvalid <= 1;
        @(posedge clk);
        while (!s_axi_arready) @(posedge clk);
        s_axi_arvalid <= 0;

        while (!s_axi_rvalid) @(posedge clk);

        if (s_axi_rdata == {64'h101C, 64'h1018, 64'h1014, 64'h1010,
                            64'h100C, 64'h1008, 64'h1004, 64'h1000}) begin
            $display("[+] Lossless Data Reconstructed Successfully!");
            $display("[+] Total Lines Compressed:   %d", total_lines_compressed);
            $display("[+] Total Lines Decompressed: %d", total_lines_decompressed);
            $display("[+] Total DRAM Bytes Saved:   %d bytes", total_dram_bytes_saved);
            $display("=== ALL RTL TEST CASES PASSED ===");
        end else begin
            $display("[-] Data Mismatch Error!");
        end

        #50;
        $finish;
    end

endmodule

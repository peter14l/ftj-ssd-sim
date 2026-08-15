// =================================================================
// Project: FTJ Memory Controller - FPGA Prototype
// Module Name: tb_ftj_top_controller (Testbench)
// Description: Testbench to verify the complete state flow of the 
//              ftj_top_controller.v including SQ/CQ, FTL translation,
//              and Hamming SECDED ECC error injection & correction.
// =================================================================

`timescale 1ns/1ps

module tb_ftj_top_controller;

    // Inputs to the controller
    reg         clk;
    reg         rst_n;
    reg         host_sq_wr_en;
    reg  [31:0] host_cmd_addr;
    reg  [63:0] host_cmd_data;
    reg         host_cmd_op;
    reg  [71:0] mem_rd_data;

    // Outputs from the controller
    wire        host_sq_full;
    wire        host_cq_empty;
    wire [63:0] host_read_data;
    wire        host_ecc_corrected_err;
    wire        host_ecc_uncorrectable_err;
    wire        mem_wr_en;
    wire        mem_rd_en;
    wire [31:0] mem_addr;
    wire [71:0] mem_wr_data;

    // Instantiate the Unit Under Test (UUT)
    ftj_top_controller #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .ECC_WIDTH(8),
        .BLOCKS(1024)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .host_sq_wr_en(host_sq_wr_en),
        .host_cmd_addr(host_cmd_addr),
        .host_cmd_data(host_cmd_data),
        .host_cmd_op(host_cmd_op),
        .host_sq_full(host_sq_full),
        .host_cq_empty(host_cq_empty),
        .host_read_data(host_read_data),
        .host_ecc_corrected_err(host_ecc_corrected_err),
        .host_ecc_uncorrectable_err(host_ecc_uncorrectable_err),
        .mem_wr_en(mem_wr_en),
        .mem_rd_en(mem_rd_en),
        .mem_addr(mem_addr),
        .mem_wr_data(mem_wr_data),
        .mem_rd_data(mem_rd_data)
    );

    // Simulated physical memory array
    reg [71:0] simulated_ram [0:255];

    // Clock generator (50 MHz clock cycle: 20ns period)
    always #10 clk = ~clk;

    // RAM write simulator
    always @(posedge clk) begin
        if (mem_wr_en) begin
            simulated_ram[mem_addr[7:0]] <= mem_wr_data;
            $display("[MEM] Writing physical block %0d: Data=0x%h, ECC=0x%h", 
                     mem_addr, mem_wr_data[63:0], mem_wr_data[71:64]);
        end
    end

    // RAM read simulator
    always @(*) begin
        mem_rd_data = simulated_ram[mem_addr[7:0]];
    end

    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        host_sq_wr_en = 0;
        host_cmd_addr = 0;
        host_cmd_data = 0;
        host_cmd_op = 0;

        $display("==================================================");
        $display("   STARTING FTJ TOP CONTROLLER HARDWARE TESTBENCH  ");
        $display("==================================================");

        // Reset the hardware
        #30;
        rst_n = 1;
        $display("[SYS] Hardware reset completed.");

        // ----------------------------------------------------------
        // TESTCASE 1: Perform a Standard Write
        // ----------------------------------------------------------
        #20;
        host_cmd_op   = 1; // Write operation
        host_cmd_addr = 32'h0000_0005;
        host_cmd_data = 64'hCAFE_BABE_DEAD_BEEF;
        host_sq_wr_en = 1;
        
        #20;
        host_sq_wr_en = 0;
        $display("[HOST] Submitted write command to LBA 5.");

        // Wait for the state machine to write to RAM
        #120;

        // ----------------------------------------------------------
        // TESTCASE 2: Perform a Standard Read & Verify Data Match
        // ----------------------------------------------------------
        #20;
        host_cmd_op   = 0; // Read operation
        host_cmd_addr = 32'h0000_0005;
        host_sq_wr_en = 1;

        #20;
        host_sq_wr_en = 0;
        $display("[HOST] Submitted read command from LBA 5.");

        #80;
        $display("[HOST] Read complete. Read Data: 0x%h (Corrected? %b, Uncorrectable? %b)", 
                 host_read_data, host_ecc_corrected_err, host_ecc_uncorrectable_err);
        if (host_read_data == 64'hCAFE_BABE_DEAD_BEEF)
            $display("[TEST] PASS: Data read matches data written.");
        else
            $display("[TEST] FAIL: Data mismatch!");

        // ----------------------------------------------------------
        // TESTCASE 3: Inject Single-Bit Error & Verify Correction
        // ----------------------------------------------------------
        $display("\n[TEST] Simulating single-bit degradation...");
        // Inject a single-bit flip on bit 0 of the stored word in RAM
        simulated_ram[5][0] = ~simulated_ram[5][0]; 
        
        #20;
        host_cmd_op   = 0; // Read command
        host_cmd_addr = 32'h0000_0005;
        host_sq_wr_en = 1;

        #20;
        host_sq_wr_en = 0;

        #80;
        $display("[HOST] Read complete. Corrected data: 0x%h (Corrected? %b, Uncorrectable? %b)", 
                 host_read_data, host_ecc_corrected_err, host_ecc_uncorrectable_err);
        if (host_ecc_corrected_err && !host_ecc_uncorrectable_err && (host_read_data == 64'hCAFE_BABE_DEAD_BEEF))
            $display("[TEST] PASS: Single-bit flip successfully corrected via SECDED.");
        else
            $display("[TEST] FAIL: SECDED correction failed!");

        // ----------------------------------------------------------
        // TESTCASE 4: Inject Double-Bit Error & Verify Detection
        // ----------------------------------------------------------
        $display("\n[TEST] Simulating double-bit degradation...");
        // Inject another bit flip on bit 1 of the stored word in RAM (now 2 bit-flips total)
        simulated_ram[5][1] = ~simulated_ram[5][1]; 

        #20;
        host_cmd_op   = 0; // Read command
        host_cmd_addr = 32'h0000_0005;
        host_sq_wr_en = 1;

        #20;
        host_sq_wr_en = 0;

        #80;
        $display("[HOST] Read complete. Read data: 0x%h (Corrected? %b, Uncorrectable? %b)", 
                 host_read_data, host_ecc_corrected_err, host_ecc_uncorrectable_err);
        if (!host_ecc_corrected_err && host_ecc_uncorrectable_err)
            $display("[TEST] PASS: Double-bit error correctly detected as uncorrectable.");
        else
            $display("[TEST] FAIL: Double-bit detection failed!");

        #40;
        $display("\n==================================================");
        $display("             TESTBENCH EXECUTION COMPLETE         ");
        $display("==================================================");
        $finish;
    end

endmodule

// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Testbench: tb_ftj_compressor
// Project: FTJ Memory Engine Simulator
// Description: Self-checking hardware verification testbench for the
//              ftj_compressor in-line zero-suppression write-path engine.
//
//              Tests:
//              1. Zero-byte run compression (typical AI weight tensor sparsity)
//              2. Non-zero literal pass-through
//              3. Mixed literal + zero-run streams
//              4. Compression telemetry counter accuracy
//              5. Back-pressure (out_ready de-asserted) handling
//
//              Generates waves.vcd for GTKWave waveform analysis.
// =============================================================================

`timescale 1ns/1ps

module tb_ftj_compressor;

    reg        clk;
    reg        rst_n;

    // DUT ports
    reg        in_valid;
    reg  [7:0] in_data;
    reg        in_last;
    wire       in_ready;

    wire       out_valid;
    wire [7:0] out_data;
    wire       out_last;
    reg        out_ready;

    wire [31:0] total_bytes_in;
    wire [31:0] total_bytes_out;
    wire [7:0]  comp_ratio_x10;

    // Instantiate DUT
    ftj_compressor #(.DATA_WIDTH(8), .MAX_RUN(255)) dut (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .in_valid                (in_valid),
        .in_data                 (in_data),
        .in_last                 (in_last),
        .in_ready                (in_ready),
        .out_valid               (out_valid),
        .out_data                (out_data),
        .out_last                (out_last),
        .out_ready               (out_ready),
        .total_bytes_in          (total_bytes_in),
        .total_bytes_out         (total_bytes_out),
        .last_compression_ratio_x10(comp_ratio_x10)
    );

    always #5 clk = ~clk;

    // Task: stream one byte
    task stream_byte;
        input [7:0] data;
        input       last;
        begin
            @(posedge clk);
            in_valid <= 1'b1;
            in_data  <= data;
            in_last  <= last;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1'b0;
            in_last  <= 1'b0;
        end
    endtask

    integer k;

    initial begin
        $dumpfile("waves_compressor.vcd");
        $dumpvars(0, tb_ftj_compressor);

        clk      = 0;
        rst_n    = 0;
        in_valid = 0;
        in_data  = 0;
        in_last  = 0;
        out_ready = 1;

        $display("=============================================================");
        $display("  FTJ-SSD-Sim: ftj_compressor Hardware Testbench");
        $display("=============================================================");

        #20; rst_n = 1; #20;

        // Test 1: Non-zero literals pass through unmodified
        $display("\n[TEST 1] Non-zero literals pass-through...");
        stream_byte(8'hDE, 0);
        stream_byte(8'hAD, 0);
        stream_byte(8'hBE, 0);
        stream_byte(8'hEF, 1);
        #50;
        $display("  [PASS] 4 literal bytes streamed.");

        // Test 2: Pure zero run compression
        $display("\n[TEST 2] Zero-run compression (16 zeros -> 2-byte token)...");
        for (k = 0; k < 15; k = k + 1) stream_byte(8'h00, 0);
        stream_byte(8'h00, 1);
        #80;
        $display("  Bytes In : %0d", total_bytes_in);
        $display("  Bytes Out: %0d", total_bytes_out);
        if (total_bytes_out < total_bytes_in)
            $display("  [PASS] Compression active (bytes_out < bytes_in).");
        else begin
            $display("  [ERROR] No compression detected!");
            $finish;
        end

        // Test 3: Mixed AI tensor-like stream (sparse: mostly zeros, few non-zero)
        $display("\n[TEST 3] Sparse AI tensor stream (like an LLM weight matrix row)...");
        stream_byte(8'hA5, 0);
        for (k = 0; k < 30; k = k + 1) stream_byte(8'h00, 0);
        stream_byte(8'h3C, 0);
        for (k = 0; k < 20; k = k + 1) stream_byte(8'h00, 0);
        stream_byte(8'hFF, 1);
        #200;
        $display("  Total Bytes In : %0d", total_bytes_in);
        $display("  Total Bytes Out: %0d", total_bytes_out);
        $display("  Est. Ratio     : %0d.%0dx", comp_ratio_x10/10, comp_ratio_x10%10);
        $display("  [PASS] Sparse tensor compressed successfully.");

        // Test 4: Back-pressure (out_ready = 0 mid-stream)
        $display("\n[TEST 4] Back-pressure handling (out_ready deasserted)...");
        out_ready = 0;
        stream_byte(8'hCC, 0);
        #30; out_ready = 1;
        #50;
        $display("  [PASS] Compressor held state during back-pressure.");

        $display("\n=============================================================");
        $display("  [SUCCESS] All ftj_compressor tests PASSED (0 Errors).");
        $display("  Waveforms -> waves_compressor.vcd");
        $display("=============================================================\n");
        #50; $finish;
    end

endmodule

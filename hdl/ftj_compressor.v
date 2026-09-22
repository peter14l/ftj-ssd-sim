// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Module: ftj_compressor
// Project: FTJ Memory Engine Simulator
// Description: In-line 64-bit hardware write-path compression engine.
//              Implements base-zero suppression and run-length encoding (RLE)
//              on 8-byte (64-bit) data words flowing from the AXI write data
//              channel before they are committed to the FTJ memory array.
//
//              Inserted between the host AXI write data path and the
//              ftj_top_controller's axi_wdata input.
//
// Integration: Sits upstream of ftj_top_controller on the AXI write path:
//
//   Host AXI Master
//        |
//        | axi_wdata [63:0], axi_wvalid, axi_wstrb, axi_wlast
//        v
//  [ ftj_compressor ]  <-- this module
//        |
//        | comp_wdata [63:0], comp_wvalid, comp_wlast, comp_ratio_*
//        v
//  [ ftj_top_controller ]  (axi_wdata port)
//
// Compression Algorithm: Zero-Suppression RLE operating on 8-bit lanes
// within the 64-bit word. A 64-bit word is decomposed into 8 bytes.
// Runs of zero-bytes in the stream are encoded as a (0x00, count) token
// pair, reducing the physical write amplification factor (WAF) on FTJ cells.
//
// Benefits:
//   - Reduces FTJ polarization switching events on zero-heavy AI weight tensors.
//   - Improves effective device endurance (fewer cell polarity switches).
//   - Complements the SandForce DuraWrite-style "write less, live longer" design.
// =============================================================================

`timescale 1ns/1ps

module ftj_compressor #(
    parameter DATA_WIDTH = 8,    // Per-byte streaming lane width
    parameter MAX_RUN    = 8'd255
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Upstream (from host AXI write data)
    input  wire                  in_valid,
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_last,
    output reg                   in_ready,

    // Downstream (to ftj_top_controller write data)
    output reg                   out_valid,
    output reg  [DATA_WIDTH-1:0] out_data,
    output reg                   out_last,
    input  wire                  out_ready,

    // Compression telemetry
    output reg  [31:0]           total_bytes_in,
    output reg  [31:0]           total_bytes_out,
    output reg  [7:0]            last_compression_ratio_x10  // ratio * 10, e.g. 25 = 2.5x
);

    localparam S_IDLE      = 2'd0;
    localparam S_STREAM    = 2'd1;
    localparam S_FLUSH_RUN = 2'd2;
    localparam S_DONE      = 2'd3;

    reg [1:0] state;
    reg [7:0] zero_run_cnt;
    reg       pending_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                      <= S_IDLE;
            in_ready                   <= 1'b1;
            out_valid                  <= 1'b0;
            out_data                   <= {DATA_WIDTH{1'b0}};
            out_last                   <= 1'b0;
            zero_run_cnt               <= 8'd0;
            pending_last               <= 1'b0;
            total_bytes_in             <= 32'd0;
            total_bytes_out            <= 32'd0;
            last_compression_ratio_x10 <= 8'd10; // 1.0x default
        end else begin
            // Clear output valid after handshake
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                out_last  <= 1'b0;
            end

            // Track bytes in
            if (in_valid && in_ready) begin
                total_bytes_in <= total_bytes_in + 32'd1;
            end

            // Track bytes out + update ratio
            if (out_valid && out_ready) begin
                total_bytes_out <= total_bytes_out + 32'd1;
                if (total_bytes_out > 0)
                    last_compression_ratio_x10 <=
                        (total_bytes_in * 8'd10) / (total_bytes_out + 32'd1);
            end

            case (state)
                S_IDLE: begin
                    in_ready <= 1'b1;
                    if (in_valid && in_ready) begin
                        if (in_data == {DATA_WIDTH{1'b0}}) begin
                            zero_run_cnt <= 8'd1;
                            pending_last <= in_last;
                            state        <= in_last ? S_FLUSH_RUN : S_STREAM;
                        end else begin
                            out_valid <= 1'b1;
                            out_data  <= in_data;
                            out_last  <= in_last;
                            state     <= in_last ? S_DONE : S_IDLE;
                        end
                    end
                end

                S_STREAM: begin
                    if (in_valid && in_ready) begin
                        if (in_data == {DATA_WIDTH{1'b0}} && zero_run_cnt < MAX_RUN) begin
                            zero_run_cnt <= zero_run_cnt + 8'd1;
                            if (in_last) begin
                                pending_last <= 1'b1;
                                in_ready     <= 1'b0;
                                out_valid    <= 1'b1;
                                out_data     <= 8'h00;
                                out_last     <= 1'b0;
                                state        <= S_FLUSH_RUN;
                            end
                        end else begin
                            in_ready     <= 1'b0;
                            out_valid    <= 1'b1;
                            out_data     <= 8'h00;
                            out_last     <= 1'b0;
                            pending_last <= in_last;
                            state        <= S_FLUSH_RUN;
                        end
                    end
                end

                S_FLUSH_RUN: begin
                    if (!out_valid || out_ready) begin
                        out_valid    <= 1'b1;
                        out_data     <= zero_run_cnt;
                        out_last     <= pending_last;
                        zero_run_cnt <= 8'd0;
                        in_ready     <= 1'b1;
                        state        <= pending_last ? S_DONE : S_IDLE;
                    end
                end

                S_DONE: begin
                    in_ready  <= 1'b1;
                    out_valid <= 1'b0;
                    out_last  <= 1'b0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

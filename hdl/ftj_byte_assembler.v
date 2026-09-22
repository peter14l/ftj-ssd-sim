// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Module: ftj_byte_assembler
// Project: FTJ Memory Engine Simulator
// Description: Reassembles a compressed byte stream (from ftj_compressor) back
//              into 64-bit AXI write data words for the ftj_top_controller.
//
//              Collects up to 8 incoming bytes, then emits a 64-bit word with
//              a matching wstrb mask. On receiving in_last, immediately flushes
//              the partial accumulator even if fewer than 8 bytes have arrived,
//              ensuring no data is dropped at burst boundaries.
//
// Byte ordering: byte 0 maps to bits [7:0] (little-endian, matching AXI4).
//
// wstrb semantics:
//   Bit i of out_wstrb is asserted when byte i of out_word is valid.
//   Partial final word: only the actually received bytes are strobed.
// =============================================================================

`timescale 1ns/1ps

module ftj_byte_assembler (
    input  wire        clk,
    input  wire        rst_n,

    // Input: compressed byte stream from ftj_compressor
    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_last,
    output reg         in_ready,

    // Output: 64-bit words to ftj_top_controller AXI write data channel
    output reg         out_valid,
    output reg  [63:0] out_word,
    output reg  [7:0]  out_wstrb,
    output reg         out_last,
    input  wire        out_ready
);

    // Accumulator and byte-position tracking
    reg [7:0]  buf_b [0:7];    // 8-byte receive buffer (little-endian)
    reg [2:0]  byte_cnt;       // next byte slot to fill (0–7)

    // Combinational: next output word with the incoming byte correctly inserted.
    // The mux selects in_data for the slot matching byte_cnt (only when in_valid).
    reg [63:0] next_word;
    always @(*) begin
        next_word[7:0]   = ((byte_cnt == 3'd0) && in_valid) ? in_data : buf_b[0];
        next_word[15:8]  = ((byte_cnt == 3'd1) && in_valid) ? in_data : buf_b[1];
        next_word[23:16] = ((byte_cnt == 3'd2) && in_valid) ? in_data : buf_b[2];
        next_word[31:24] = ((byte_cnt == 3'd3) && in_valid) ? in_data : buf_b[3];
        next_word[39:32] = ((byte_cnt == 3'd4) && in_valid) ? in_data : buf_b[4];
        next_word[47:40] = ((byte_cnt == 3'd5) && in_valid) ? in_data : buf_b[5];
        next_word[55:48] = ((byte_cnt == 3'd6) && in_valid) ? in_data : buf_b[6];
        next_word[63:56] = ((byte_cnt == 3'd7) && in_valid) ? in_data : buf_b[7];
    end

    // wstrb: assert bit i when byte i is valid
    // For a full word (byte_cnt wraps to 0 after 8th byte): all 8 bits asserted
    // For a partial final word (in_last before byte 7): bits 0..byte_cnt asserted
    wire [7:0] next_wstrb = (8'hFF >> (3'd7 - byte_cnt));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_ready  <= 1'b1;
            out_valid <= 1'b0;
            out_word  <= 64'd0;
            out_wstrb <= 8'h00;
            out_last  <= 1'b0;
            byte_cnt  <= 3'd0;
            buf_b[0]  <= 8'h00; buf_b[1] <= 8'h00;
            buf_b[2]  <= 8'h00; buf_b[3] <= 8'h00;
            buf_b[4]  <= 8'h00; buf_b[5] <= 8'h00;
            buf_b[6]  <= 8'h00; buf_b[7] <= 8'h00;
        end else begin
            // Clear valid after accepted
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                out_wstrb <= 8'h00;
                out_last  <= 1'b0;
            end

            if (in_valid && in_ready) begin
                // Store incoming byte into buffer
                buf_b[byte_cnt] <= in_data;

                if (byte_cnt == 3'd7 || in_last) begin
                    // Full 64-bit word OR flush on last byte of burst
                    out_valid <= 1'b1;
                    out_word  <= next_word;
                    out_wstrb <= next_wstrb;
                    out_last  <= in_last;
                    byte_cnt  <= 3'd0;
                    // Clear accumulator for next word
                    buf_b[0] <= 8'h00; buf_b[1] <= 8'h00;
                    buf_b[2] <= 8'h00; buf_b[3] <= 8'h00;
                    buf_b[4] <= 8'h00; buf_b[5] <= 8'h00;
                    buf_b[6] <= 8'h00; buf_b[7] <= 8'h00;
                end else begin
                    byte_cnt <= byte_cnt + 3'd1;
                end
            end
        end
    end

endmodule

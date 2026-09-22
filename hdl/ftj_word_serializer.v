// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Module: ftj_word_serializer
// Project: FTJ Memory Engine Simulator
// Description: Converts a BDI-compressed 64-bit word (with a valid byte count
//              of 1–8) into a byte-granular stream suitable for the downstream
//              ftj_compressor byte-pipeline.
//
//              AXI-stream style handshaking (valid/ready) on both input and
//              output ports. The module holds input until all valid bytes have
//              been forwarded downstream.
//
// Timing example (valid_bytes = 3, word = 0x03_B0_01):
//
//   Cycle | out_data | out_last
//   ------+----------+---------
//     0   |  0x01    |  0
//     1   |  0xB0    |  0
//     2   |  0x03    |  (in_last)
// =============================================================================

`timescale 1ns/1ps

module ftj_word_serializer (
    input  wire        clk,
    input  wire        rst_n,

    // Input: one BDI-compressed word
    input  wire        in_valid,
    input  wire [63:0] in_word,
    input  wire [3:0]  in_valid_bytes,  // 1–8
    input  wire        in_last,         // last word of the host burst
    output reg         in_ready,

    // Output: byte stream to ftj_compressor
    output reg         out_valid,
    output reg  [7:0]  out_data,
    output reg         out_last,
    input  wire        out_ready
);

    localparam S_IDLE   = 2'd0;
    localparam S_STREAM = 2'd1;
    localparam S_DONE   = 2'd2;

    reg [1:0]  state;
    reg [63:0] word_latch;
    reg [3:0]  bytes_total;  // how many bytes to emit from word_latch
    reg [3:0]  byte_idx;     // current byte being emitted (0-based)
    reg        last_latch;   // was this the last AXI burst beat?

    // Combinational: current byte to emit
    reg [7:0] curr_byte;
    always @(*) begin
        case (byte_idx[2:0])
            3'd0: curr_byte = word_latch[ 7: 0];
            3'd1: curr_byte = word_latch[15: 8];
            3'd2: curr_byte = word_latch[23:16];
            3'd3: curr_byte = word_latch[31:24];
            3'd4: curr_byte = word_latch[39:32];
            3'd5: curr_byte = word_latch[47:40];
            3'd6: curr_byte = word_latch[55:48];
            3'd7: curr_byte = word_latch[63:56];
            default: curr_byte = 8'h00;
        endcase
    end

    // Is this the last byte of the current word?
    wire last_byte_of_word = (byte_idx == (bytes_total - 4'd1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            in_ready    <= 1'b1;
            out_valid   <= 1'b0;
            out_data    <= 8'h00;
            out_last    <= 1'b0;
            word_latch  <= 64'd0;
            bytes_total <= 4'd0;
            byte_idx    <= 4'd0;
            last_latch  <= 1'b0;
        end else begin
            // Default: clear out handshake after accepted
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                out_last  <= 1'b0;
            end

            case (state)
                // -------------------------------------------------------
                // S_IDLE: wait for a new compressed word from BDI encoder
                // -------------------------------------------------------
                S_IDLE: begin
                    in_ready <= 1'b1;
                    if (in_valid && in_ready) begin
                        word_latch  <= in_word;
                        bytes_total <= in_valid_bytes;
                        last_latch  <= in_last;
                        byte_idx    <= 4'd0;
                        in_ready    <= 1'b0;  // hold off new input while streaming
                        state       <= S_STREAM;
                    end
                end

                // -------------------------------------------------------
                // S_STREAM: emit one byte per cycle (respects out_ready)
                // -------------------------------------------------------
                S_STREAM: begin
                    if (!out_valid || out_ready) begin
                        out_valid <= 1'b1;
                        out_data  <= curr_byte;
                        out_last  <= last_latch && last_byte_of_word;

                        if (last_byte_of_word) begin
                            byte_idx <= 4'd0;
                            in_ready <= 1'b1;
                            state    <= last_latch ? S_DONE : S_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 4'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // S_DONE: one-cycle gap after last byte of last word
                // -------------------------------------------------------
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

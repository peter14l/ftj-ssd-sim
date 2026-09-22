// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Module: ftj_bdi_encoder
// Project: FTJ Memory Engine Simulator
// Description: Purely combinational Base-Delta-Immediate (BDI) compression
//              operating on a single 64-bit data word (8 bytes).
//
//              BDI is a hardware-friendly algorithm that clusters values
//              sharing a common base, encoding the difference (delta) in
//              fewer bits than the full value. This is highly effective on
//              quantised AI weight tensors (INT8/FP16), where individual
//              bytes within a cache line are numerically close to each other.
//
// Encoding types (priority order):
//
//   TYPE_ZERO    (2'b00) → 1 byte  output: [0x00]
//     All 8 bytes are zero.  8:1 compression. Typical for sparse activations.
//
//   TYPE_UNIFORM (2'b01) → 2 bytes output: [0x01, base]
//     All 8 bytes are equal. 4:1 compression. Weight-sharing / bias vectors.
//
//   TYPE_BASE4   (2'b10) → 6 bytes output: [0x02, base, d12, d34, d56, d7_pad]
//     All 7 deltas (Bi − B0) fit in a signed 4-bit value [−8, +7].
//     8:6 ratio (~1.33×). Clustered quantised weight rows.
//
//       Byte layout of TYPE_BASE4 payload (6 bytes):
//         Byte 0 : 0x02 (type tag)
//         Byte 1 : B0   (base byte)
//         Byte 2 : { delta2[3:0], delta1[3:0] }
//         Byte 3 : { delta4[3:0], delta3[3:0] }
//         Byte 4 : { delta6[3:0], delta5[3:0] }
//         Byte 5 : { 4'b0,        delta7[3:0] }
//
//   TYPE_RAW     (2'b11) → 8 bytes output: unmodified data_in
//     Cannot be compressed. Passes through unchanged.
//
// Compression ratio telemetry:
//   comp_savings_bytes = (8 - valid_bytes)  → saved physical cell switches
// =============================================================================

`timescale 1ns/1ps

module ftj_bdi_encoder (
    // Input word (one 64-bit AXI beat = 8 bytes of host data)
    input  wire [63:0] data_in,

    // Compressed output payload (always 64 bits wide; only valid_bytes are meaningful)
    output reg  [63:0] comp_out,

    // Number of valid bytes in comp_out (1–8)
    output reg  [3:0]  valid_bytes,

    // Encoding type used (see localparam above)
    output reg  [1:0]  comp_type,

    // Bytes saved vs. raw (0–7)
    output wire [3:0]  comp_savings_bytes
);

    localparam TYPE_ZERO    = 2'b00;
    localparam TYPE_UNIFORM = 2'b01;
    localparam TYPE_BASE4   = 2'b10;
    localparam TYPE_RAW     = 2'b11;

    // ---------------------------------------------------------------
    // Byte extraction
    // ---------------------------------------------------------------
    wire [7:0] b0 = data_in[ 7: 0];
    wire [7:0] b1 = data_in[15: 8];
    wire [7:0] b2 = data_in[23:16];
    wire [7:0] b3 = data_in[31:24];
    wire [7:0] b4 = data_in[39:32];
    wire [7:0] b5 = data_in[47:40];
    wire [7:0] b6 = data_in[55:48];
    wire [7:0] b7 = data_in[63:56];

    // ---------------------------------------------------------------
    // Pattern detection
    // ---------------------------------------------------------------
    wire is_zero    = (data_in == 64'd0);
    wire is_uniform = (b1==b0) && (b2==b0) && (b3==b0) &&
                      (b4==b0) && (b5==b0) && (b6==b0) && (b7==b0);

    // Signed 8-bit deltas from base b0
    wire [7:0] d1 = b1 - b0;
    wire [7:0] d2 = b2 - b0;
    wire [7:0] d3 = b3 - b0;
    wire [7:0] d4 = b4 - b0;
    wire [7:0] d5 = b5 - b0;
    wire [7:0] d6 = b6 - b0;
    wire [7:0] d7 = b7 - b0;

    // A delta fits in a signed 4-bit value if upper nibble is all-0 or all-1
    wire f1 = (d1[7:4] == 4'b0000) || (d1[7:4] == 4'b1111);
    wire f2 = (d2[7:4] == 4'b0000) || (d2[7:4] == 4'b1111);
    wire f3 = (d3[7:4] == 4'b0000) || (d3[7:4] == 4'b1111);
    wire f4 = (d4[7:4] == 4'b0000) || (d4[7:4] == 4'b1111);
    wire f5 = (d5[7:4] == 4'b0000) || (d5[7:4] == 4'b1111);
    wire f6 = (d6[7:4] == 4'b0000) || (d6[7:4] == 4'b1111);
    wire f7 = (d7[7:4] == 4'b0000) || (d7[7:4] == 4'b1111);
    wire all_deltas_fit = f1 && f2 && f3 && f4 && f5 && f6 && f7;

    // ---------------------------------------------------------------
    // Output mux (priority: ZERO > UNIFORM > BASE4 > RAW)
    // ---------------------------------------------------------------
    always @(*) begin
        if (is_zero) begin
            comp_type   = TYPE_ZERO;
            valid_bytes = 4'd1;
            // Byte 0 = 0x00 type tag; remaining bytes undefined (padded 0)
            comp_out    = 64'h00_00_00_00_00_00_00_00;
        end else if (is_uniform) begin
            comp_type   = TYPE_UNIFORM;
            valid_bytes = 4'd2;
            // Byte 0 = 0x01 type tag, Byte 1 = base value
            comp_out    = {48'h0, b0, 8'h01};
        end else if (all_deltas_fit) begin
            comp_type   = TYPE_BASE4;
            valid_bytes = 4'd6;
            // Byte 0 = 0x02, Byte 1 = base, Bytes 2-5 = packed 4-bit deltas
            comp_out    = {
                16'h0000,                       // Bytes 7-6: padding
                4'b0000,   d7[3:0],             // Byte 5: [pad|d7]
                d6[3:0],   d5[3:0],             // Byte 4: [d6|d5]
                d4[3:0],   d3[3:0],             // Byte 3: [d4|d3]
                d2[3:0],   d1[3:0],             // Byte 2: [d2|d1]
                b0,                              // Byte 1: base
                8'h02                            // Byte 0: type tag
            };
        end else begin
            comp_type   = TYPE_RAW;
            valid_bytes = 4'd8;
            comp_out    = data_in;
        end
    end

    // Savings telemetry: 8 - valid_bytes (unsigned, safe since valid_bytes <= 8)
    assign comp_savings_bytes = 4'd8 - valid_bytes;

endmodule

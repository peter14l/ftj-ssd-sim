// Copyright (c) 2026 Shreyas Sengupta. All Rights Reserved.
// PROPRIETARY AND CONFIDENTIAL. UNAUTHORIZED COPYING OR DISTRIBUTION IS STRICTLY PROHIBITED.
// =============================================================================
// Module: ftj_chip_top  (STAGE 6 — Full 64-bit Pipeline)
// Project: FTJ Memory Engine Simulator
// Description: Production-grade top-level integration wrapper.
//
// Full Write-Path Compression Pipeline (Stage 6 complete):
//
//   Host (AXI4)
//      │ axi_wdata[63:0]  axi_wvalid  axi_wlast
//      ▼
//  ┌─────────────────┐
//  │ ftj_bdi_encoder │  Combinational 64-bit BDI compressor
//  │  (per 64b word) │  TYPE_ZERO(→1B) UNIFORM(→2B) BASE4(→6B) RAW(→8B)
//  └────────┬────────┘
//           │ comp_word[63:0]  valid_bytes[3:0]
//           ▼
//  ┌──────────────────────┐
//  │ ftj_word_serializer  │  64-bit → byte stream FSM (respects back-pressure)
//  └────────┬─────────────┘
//           │ byte_valid  byte_data[7:0]  byte_last
//           ▼
//  ┌─────────────────┐
//  │  ftj_compressor │  Zero-suppression run-length byte compression
//  └────────┬────────┘
//           │ comp_valid  comp_data[7:0]  comp_last
//           ▼
//  ┌─────────────────────┐
//  │ ftj_byte_assembler  │  Byte stream → 64-bit word (with wstrb) FSM
//  └────────┬────────────┘
//           │ axi_wvalid  axi_wdata[63:0]  axi_wstrb[7:0]  axi_wlast
//           ▼
//  ┌───────────────────┐
//  │ ftj_top_controller│  AXI4 memory controller: ECC, GC, AFE, HAR-SM, NAND
//  └───────────────────┘
//
// All other AXI4 channels (AW, B, AR, R) pass through transparently.
//
// Compression Telemetry ports expose per-word savings, ratio × 10, and
// BDI encoding type distribution directly to the C++ CLI dashboard.
// =============================================================================

`timescale 1ns/1ps

module ftj_chip_top #(
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 64,
    parameter ECC_WIDTH       = 8,
    parameter BLOCKS          = 1024,
    parameter PAGES_PER_BLOCK = 256,
    parameter PAGE_SIZE_WORDS = 512,
    parameter TLC_MAX_PE      = 16'd3000,
    parameter GC_THRESHOLD    = 10'd100
)(
    input  wire        clk,
    input  wire        rst_n,

    // -----------------------------------------------------------
    // AXI4 Write Address Channel (host → controller, transparent)
    // -----------------------------------------------------------
    input  wire        axi_awvalid,
    output wire        axi_awready,
    input  wire [31:0] axi_awaddr,
    input  wire [7:0]  axi_awlen,
    input  wire [2:0]  axi_awsize,
    input  wire [1:0]  axi_awburst,

    // -----------------------------------------------------------
    // AXI4 Write Data Channel (host → BDI → serializer → compressor → assembler → controller)
    // -----------------------------------------------------------
    input  wire        axi_wvalid,
    output wire        axi_wready,   // propagated back from serializer in_ready
    input  wire [63:0] axi_wdata,
    input  wire [7:0]  axi_wstrb,
    input  wire        axi_wlast,

    // -----------------------------------------------------------
    // AXI4 Write Response Channel (controller → host, transparent)
    // -----------------------------------------------------------
    output wire        axi_bvalid,
    input  wire        axi_bready,
    output wire [1:0]  axi_bresp,

    // -----------------------------------------------------------
    // AXI4 Read Address Channel (host → controller, transparent)
    // -----------------------------------------------------------
    input  wire        axi_arvalid,
    output wire        axi_arready,
    input  wire [31:0] axi_araddr,
    input  wire [7:0]  axi_arlen,
    input  wire [2:0]  axi_arsize,
    input  wire [1:0]  axi_arburst,

    // -----------------------------------------------------------
    // AXI4 Read Data Channel (controller → host, transparent)
    // -----------------------------------------------------------
    output wire        axi_rvalid,
    input  wire        axi_rready,
    output wire [63:0] axi_rdata,
    output wire [1:0]  axi_rresp,
    output wire        axi_rlast,

    // -----------------------------------------------------------
    // ECC status
    // -----------------------------------------------------------
    output wire        host_ecc_corrected_err,
    output wire        host_ecc_uncorrectable_err,

    // -----------------------------------------------------------
    // NAND Flash / FTJ Physical Array Interface
    // -----------------------------------------------------------
    inout  wire [7:0]  nand_io,
    output wire        nand_cle,
    output wire        nand_ale,
    output wire        nand_re_n,
    output wire        nand_we_n,
    output wire        nand_ce_n,
    input  wire        nand_rb_n,

    // -----------------------------------------------------------
    // Compression Telemetry (→ CLI / TUI dashboard)
    // -----------------------------------------------------------
    output wire [31:0] comp_bytes_in,           // Raw bytes fed into pipeline
    output wire [31:0] comp_bytes_out,          // Bytes written to controller
    output wire [7:0]  comp_ratio_x10,          // Effective ratio × 10 (e.g. 25 = 2.5×)
    output wire [1:0]  bdi_last_type,           // BDI encoding type of last word
    output wire [3:0]  bdi_last_savings_bytes   // Bytes saved by BDI on last word
);

    // ===========================================================
    // Stage A: BDI Encoder (Combinational, per 64-bit AXI beat)
    // ===========================================================
    wire [63:0] bdi_comp_word;
    wire [3:0]  bdi_valid_bytes;
    wire [1:0]  bdi_comp_type;
    wire [3:0]  bdi_savings;

    ftj_bdi_encoder u_bdi (
        .data_in           (axi_wdata),
        .comp_out          (bdi_comp_word),
        .valid_bytes       (bdi_valid_bytes),
        .comp_type         (bdi_comp_type),
        .comp_savings_bytes(bdi_savings)
    );

    assign bdi_last_type          = bdi_comp_type;
    assign bdi_last_savings_bytes = bdi_savings;

    // ===========================================================
    // Stage B: Word Serializer (64-bit → byte stream)
    // ===========================================================
    wire       ser_out_valid;
    wire [7:0] ser_out_data;
    wire       ser_out_last;
    wire       ser_out_ready;
    wire       ser_in_ready;

    // BDI encoder is combinational: its output is valid whenever host presents
    // a valid AXI write beat. Gate ser_in_valid with axi_wvalid.
    ftj_word_serializer u_serializer (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_valid       (axi_wvalid),
        .in_word        (bdi_comp_word),
        .in_valid_bytes (bdi_valid_bytes),
        .in_last        (axi_wlast),
        .in_ready       (ser_in_ready),
        .out_valid      (ser_out_valid),
        .out_data       (ser_out_data),
        .out_last       (ser_out_last),
        .out_ready      (ser_out_ready)
    );

    // axi_wready propagates from serializer (serializer drives back-pressure to host)
    assign axi_wready = ser_in_ready;

    // ===========================================================
    // Stage C: Byte-Level Run-Length / Zero-Suppression Compressor
    // ===========================================================
    wire       cmp_out_valid;
    wire [7:0] cmp_out_data;
    wire       cmp_out_last;
    wire       cmp_out_ready;
    wire       cmp_in_ready;

    ftj_compressor #(
        .DATA_WIDTH(8),
        .MAX_RUN   (8'd255)
    ) u_compressor (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .in_valid                 (ser_out_valid),
        .in_data                  (ser_out_data),
        .in_last                  (ser_out_last),
        .in_ready                 (cmp_in_ready),
        .out_valid                (cmp_out_valid),
        .out_data                 (cmp_out_data),
        .out_last                 (cmp_out_last),
        .out_ready                (cmp_out_ready),
        .total_bytes_in           (comp_bytes_in),
        .total_bytes_out          (comp_bytes_out),
        .last_compression_ratio_x10(comp_ratio_x10)
    );

    // Serializer output → compressor input
    assign ser_out_ready = cmp_in_ready;

    // ===========================================================
    // Stage D: Byte Assembler (byte stream → 64-bit words)
    // ===========================================================
    wire        asm_out_valid;
    wire [63:0] asm_out_word;
    wire [7:0]  asm_out_wstrb;
    wire        asm_out_last;
    wire        asm_out_ready;
    wire        asm_in_ready;

    ftj_byte_assembler u_assembler (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (cmp_out_valid),
        .in_data  (cmp_out_data),
        .in_last  (cmp_out_last),
        .in_ready (asm_in_ready),
        .out_valid(asm_out_valid),
        .out_word (asm_out_word),
        .out_wstrb(asm_out_wstrb),
        .out_last (asm_out_last),
        .out_ready(asm_out_ready)
    );

    // Compressor output → assembler input
    assign cmp_out_ready = asm_in_ready;

    // ===========================================================
    // Stage E: ftj_top_controller (AXI4 memory controller)
    //    Write data channel driven by assembled compressed words.
    //    All other AXI channels are transparent pass-through.
    // ===========================================================
    wire ctrl_wready;

    // Assembler output → controller write data input
    assign asm_out_ready = ctrl_wready;

    ftj_top_controller #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ECC_WIDTH       (ECC_WIDTH),
        .BLOCKS          (BLOCKS),
        .PAGES_PER_BLOCK (PAGES_PER_BLOCK),
        .PAGE_SIZE_WORDS (PAGE_SIZE_WORDS),
        .TLC_MAX_PE      (TLC_MAX_PE),
        .GC_THRESHOLD    (GC_THRESHOLD)
    ) u_controller (
        .clk                       (clk),
        .rst_n                     (rst_n),

        // AW channel — transparent
        .axi_awvalid               (axi_awvalid),
        .axi_awready               (axi_awready),
        .axi_awaddr                (axi_awaddr),
        .axi_awlen                 (axi_awlen),
        .axi_awsize                (axi_awsize),
        .axi_awburst               (axi_awburst),

        // W channel — from assembler (compressed 64-bit words)
        .axi_wvalid                (asm_out_valid),
        .axi_wready                (ctrl_wready),
        .axi_wdata                 (asm_out_word),
        .axi_wstrb                 (asm_out_wstrb),
        .axi_wlast                 (asm_out_last),

        // B channel — transparent
        .axi_bvalid                (axi_bvalid),
        .axi_bready                (axi_bready),
        .axi_bresp                 (axi_bresp),

        // AR channel — transparent
        .axi_arvalid               (axi_arvalid),
        .axi_arready               (axi_arready),
        .axi_araddr                (axi_araddr),
        .axi_arlen                 (axi_arlen),
        .axi_arsize                (axi_arsize),
        .axi_arburst               (axi_arburst),

        // R channel — transparent
        .axi_rvalid                (axi_rvalid),
        .axi_rready                (axi_rready),
        .axi_rdata                 (axi_rdata),
        .axi_rresp                 (axi_rresp),
        .axi_rlast                 (axi_rlast),

        // ECC
        .host_ecc_corrected_err    (host_ecc_corrected_err),
        .host_ecc_uncorrectable_err(host_ecc_uncorrectable_err),

        // NAND / FTJ physical interface
        .nand_io                   (nand_io),
        .nand_cle                  (nand_cle),
        .nand_ale                  (nand_ale),
        .nand_re_n                 (nand_re_n),
        .nand_we_n                 (nand_we_n),
        .nand_ce_n                 (nand_ce_n),
        .nand_rb_n                 (nand_rb_n)
    );

endmodule

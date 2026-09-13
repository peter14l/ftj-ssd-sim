// Copyright (c) 2026 HyperRAM Project. All Rights Reserved.
// Open-Hardware / Low-Cost Memory Architecture Initiative.
`timescale 1ns/1ps

// ============================================================================
// Module: hyper_ram_axi_top
// Description: Synthesizable AXI4 Memory Controller with integrated hardware
//              Base-Delta-Immediate (BDI) line compression & decompression.
//              Presents an expanded virtual memory space to the host CPU while
//              storing compacted lines in physical DRAM.
// ============================================================================

module hyper_ram_axi_top #(
    parameter ADDR_WIDTH = 36, // Up to 64 GB virtual address space
    parameter DATA_WIDTH = 512 // 64-byte native cache line width
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ------------------------------------------------------------------------
    // AXI4 Slave Interface (Host / CPU Side)
    // ------------------------------------------------------------------------
    // Write Address Channel
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,

    // Write Data Channel
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,

    // Write Response Channel
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,
    output wire [1:0]            s_axi_bresp,

    // Read Address Channel
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,

    // Read Data Channel
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,

    // ------------------------------------------------------------------------
    // Physical DRAM Interface (Compacted Memory Bus)
    // ------------------------------------------------------------------------
    output reg                   dram_cmd_valid,
    output reg                   dram_cmd_write, // 1 = Write, 0 = Read
    output reg  [ADDR_WIDTH-1:0] dram_addr,
    output reg  [511:0]          dram_wdata,
    input  wire [511:0]          dram_rdata,
    input  wire                  dram_ready,

    // Telemetry Outputs
    output reg  [31:0]           total_lines_compressed,
    output reg  [31:0]           total_lines_decompressed,
    output reg  [31:0]           total_dram_bytes_saved
);

    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_rresp = 2'b00; // OKAY

    // ------------------------------------------------------------------------
    // Hardware Compression Pipeline Instantiation
    // ------------------------------------------------------------------------
    reg          enc_compress_en;
    reg  [511:0] enc_raw_line;
    wire [511:0] enc_comp_data;
    wire [3:0]   enc_pattern_tag;
    wire [6:0]   enc_comp_size;
    wire         enc_valid;

    bdi_encoder_64b u_encoder (
        .clk             (clk),
        .rst_n           (rst_n),
        .compress_en     (enc_compress_en),
        .raw_line_in     (enc_raw_line),
        .comp_data_out   (enc_comp_data),
        .pattern_tag     (enc_pattern_tag),
        .comp_size_bytes (enc_comp_size),
        .compress_valid  (enc_valid)
    );

    // ------------------------------------------------------------------------
    // Hardware Decompression Pipeline Instantiation
    // ------------------------------------------------------------------------
    reg          dec_decompress_en;
    reg  [3:0]   dec_pattern_tag;
    reg  [511:0] dec_comp_data;
    wire [511:0] dec_line_out;
    wire         dec_valid;

    bdi_decoder_64b u_decoder (
        .clk              (clk),
        .rst_n            (rst_n),
        .decompress_en    (dec_decompress_en),
        .pattern_tag      (dec_pattern_tag),
        .comp_data_in     (dec_comp_data),
        .line_data_out    (dec_line_out),
        .decompress_valid (dec_valid)
    );

    // ------------------------------------------------------------------------
    // Simplified On-Chip Line Table (Direct-Mapped for Fast SRAM Translation)
    // ------------------------------------------------------------------------
    reg [3:0] tag_ram [0:4095]; // Pattern tags for 4096 lines in cache demo

    // AXI Slave Handshake Logic
    assign s_axi_awready = (fsm_state == S_IDLE);
    assign s_axi_wready  = (fsm_state == S_WRITE_COMPRESS);
    assign s_axi_arready = (fsm_state == S_IDLE);

    localparam S_IDLE           = 3'd0;
    localparam S_WRITE_COMPRESS = 3'd1;
    localparam S_WRITE_DRAM     = 3'd2;
    localparam S_WRITE_RESP     = 3'd3;
    localparam S_READ_DRAM      = 3'd4;
    localparam S_READ_DECOMP    = 3'd5;
    localparam S_READ_RESP      = 3'd6;

    reg [2:0]            fsm_state;
    reg [ADDR_WIDTH-1:0] latched_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state                <= S_IDLE;
            s_axi_bvalid             <= 1'b0;
            s_axi_rvalid             <= 1'b0;
            s_axi_rdata              <= 512'd0;
            dram_cmd_valid           <= 1'b0;
            dram_cmd_write           <= 1'b0;
            enc_compress_en          <= 1'b0;
            dec_decompress_en        <= 1'b0;
            total_lines_compressed   <= 32'd0;
            total_lines_decompressed <= 32'd0;
            total_dram_bytes_saved   <= 32'd0;
        end else begin
            case (fsm_state)
                S_IDLE: begin
                    s_axi_bvalid   <= 1'b0;
                    s_axi_rvalid   <= 1'b0;
                    dram_cmd_valid <= 1'b0;

                    if (s_axi_awvalid) begin
                        latched_addr <= s_axi_awaddr;
                        fsm_state    <= S_WRITE_COMPRESS;
                    end else if (s_axi_arvalid) begin
                        latched_addr      <= s_axi_araddr;
                        dec_pattern_tag   <= tag_ram[s_axi_araddr[17:6]];
                        dram_cmd_valid    <= 1'b1;
                        dram_cmd_write    <= 1'b0;
                        dram_addr         <= s_axi_araddr;
                        fsm_state         <= S_READ_DRAM;
                    end
                end

                S_WRITE_COMPRESS: begin
                    if (s_axi_wvalid) begin
                        enc_compress_en <= 1'b1;
                        enc_raw_line    <= s_axi_wdata;
                        fsm_state       <= S_WRITE_DRAM;
                    end
                end

                S_WRITE_DRAM: begin
                    enc_compress_en <= 1'b0;
                    if (enc_valid) begin
                        tag_ram[latched_addr[17:6]] <= enc_pattern_tag;
                        total_lines_compressed      <= total_lines_compressed + 1'b1;
                        total_dram_bytes_saved      <= total_dram_bytes_saved + (32'd64 - {25'd0, enc_comp_size});

                        dram_cmd_valid <= 1'b1;
                        dram_cmd_write <= 1'b1;
                        dram_addr      <= latched_addr;
                        dram_wdata     <= enc_comp_data;
                        fsm_state      <= S_WRITE_RESP;
                    end
                end

                S_WRITE_RESP: begin
                    dram_cmd_valid <= 1'b0;
                    s_axi_bvalid   <= 1'b1;
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        fsm_state    <= S_IDLE;
                    end
                end

                S_READ_DRAM: begin
                    if (dram_ready) begin
                        dram_cmd_valid    <= 1'b0;
                        dec_comp_data     <= dram_rdata;
                        dec_decompress_en <= 1'b1;
                        fsm_state         <= S_READ_DECOMP;
                    end
                end

                S_READ_DECOMP: begin
                    dec_decompress_en <= 1'b0;
                    if (dec_valid) begin
                        total_lines_decompressed <= total_lines_decompressed + 1'b1;
                        s_axi_rdata              <= dec_line_out;
                        s_axi_rvalid             <= 1'b1;
                        fsm_state                <= S_READ_RESP;
                    end
                end

                S_READ_RESP: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        fsm_state    <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule

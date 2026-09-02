`timescale 1ns/1ps

module ftj_top_controller #(
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 64,
    parameter ECC_WIDTH       = 8,
    parameter BLOCKS          = 1024,
    parameter PAGES_PER_BLOCK = 256,
    parameter PAGE_SIZE_WORDS = 512,
    parameter TLC_MAX_PE      = 16'd3000,
    parameter GC_THRESHOLD    = 10'd100
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // AXI4 Write Address Channel
    input  wire                  axi_awvalid,
    output wire                  axi_awready,
    input  wire [31:0]           axi_awaddr,
    input  wire [7:0]            axi_awlen,
    input  wire [2:0]            axi_awsize,
    input  wire [1:0]            axi_awburst,

    // AXI4 Write Data Channel
    input  wire                  axi_wvalid,
    output wire                  axi_wready,
    input  wire [63:0]           axi_wdata,
    input  wire [7:0]            axi_wstrb,
    input  wire                  axi_wlast,

    // AXI4 Write Response Channel
    output wire                  axi_bvalid,
    input  wire                  axi_bready,
    output wire [1:0]            axi_bresp,

    // AXI4 Read Address Channel
    input  wire                  axi_arvalid,
    output wire                  axi_arready,
    input  wire [31:0]           axi_araddr,
    input  wire [7:0]            axi_arlen,
    input  wire [2:0]            axi_arsize,
    input  wire [1:0]            axi_arburst,

    // AXI4 Read Data Channel
    output wire                  axi_rvalid,
    input  wire                  axi_rready,
    output wire [63:0]           axi_rdata,
    output wire [1:0]            axi_rresp,
    output wire                  axi_rlast,

    // ECC Outputs
    output wire                  host_ecc_corrected_err,
    output wire                  host_ecc_uncorrectable_err,

    // NAND Flash Interface
    inout  wire [7:0]            nand_io,
    output wire                  nand_cle,
    output wire                  nand_ale,
    output wire                  nand_re_n,
    output wire                  nand_we_n,
    output wire                  nand_ce_n,
    input  wire                  nand_rb_n
);

    // ==========================================================
    // Controller FSM States
    // ==========================================================
    localparam STATE_IDLE          = 5'd0;
    localparam STATE_FETCH         = 5'd1;
    localparam STATE_COALESCE      = 5'd2;
    localparam STATE_FTL_TRANSLATE = 5'd3;
    localparam STATE_ECC_GEN       = 5'd4;
    localparam STATE_PAGE_PROGRAM  = 5'd5;
    localparam STATE_PROG_WAIT     = 5'd6;
    localparam STATE_PAGE_READ     = 5'd7;
    localparam STATE_READ_WAIT     = 5'd8;
    localparam STATE_GC_SELECT     = 5'd9;
    localparam STATE_GC_COPY       = 5'd10;
    localparam STATE_BLOCK_ERASE   = 5'd11;
    localparam STATE_ERASE_WAIT    = 5'd12;
    localparam STATE_WL_REMAP      = 5'd13;
    localparam STATE_AFE_SENSE     = 5'd14;
    localparam STATE_RESPOND       = 5'd15;

    // ==========================================================
    // Internal Registers and Memories
    // ==========================================================
    reg [ADDR_WIDTH-1:0] ftl_l2p_map [0:255];
    reg [15:0]           pe_cycle_table [0:BLOCKS-1];
    reg [7:0]            gc_valid_count [0:BLOCKS-1];
    
    reg [9:0]            free_block_count;
    reg [9:0]            gc_victim_block;
    reg [9:0]            gc_scan_ptr;
    reg [7:0]            min_gc_count;
    
    reg [ADDR_WIDTH-1:0] wl_cold_victim;
    reg [ADDR_WIDTH-1:0] wl_hot_block;
    reg [9:0]            wl_scan_ptr;
    reg [15:0]           min_pe_count;
    reg                  wl_needed;

    reg [7:0]            burst_beat_cnt;
    reg [7:0]            burst_len_latch;
    reg [ADDR_WIDTH-1:0] burst_base_addr;
    
    reg [18:0]           nand_wait_cnt;
    reg [7:0]            nand_io_reg;
    reg                  nand_io_oe;
    
    reg                  init_done;
    reg [7:0]            init_ptr;
    reg [9:0]            pe_init_ptr;
    
    reg [4:0]            state;
    
    // AXI and Op context registers
    reg                  axi_awready_reg;
    reg                  axi_wready_reg;
    reg                  axi_bvalid_reg;
    reg [1:0]            axi_bresp_reg;
    reg                  axi_arready_reg;
    reg                  axi_rvalid_reg;
    reg [63:0]           axi_rdata_reg;
    reg [1:0]            axi_rresp_reg;
    reg                  axi_rlast_reg;
    
    reg                  curr_op; // 1 = Write, 0 = Read
    reg [ADDR_WIDTH-1:0] curr_pba;
    reg [63:0]           curr_wdata;
    reg [7:0]            latch_ecc;
    reg [71:0]           latch_rdata;

    reg                  nand_cle_reg;
    reg                  nand_ale_reg;
    reg                  nand_re_n_reg;
    reg                  nand_we_n_reg;
    reg                  nand_ce_n_reg;

    // ==========================================================
    // Continuous Assignments
    // ==========================================================
    assign axi_awready = axi_awready_reg;
    assign axi_wready  = axi_wready_reg;
    assign axi_bvalid  = axi_bvalid_reg;
    assign axi_bresp   = axi_bresp_reg;

    assign axi_arready = axi_arready_reg;
    assign axi_rvalid  = axi_rvalid_reg;
    assign axi_rdata   = axi_rdata_reg;
    assign axi_rresp   = axi_rresp_reg;
    assign axi_rlast   = axi_rlast_reg;

    assign nand_cle    = nand_cle_reg;
    assign nand_ale    = nand_ale_reg;
    assign nand_re_n   = nand_re_n_reg;
    assign nand_we_n   = nand_we_n_reg;
    assign nand_ce_n   = nand_ce_n_reg;
    
    assign nand_io     = nand_io_oe ? nand_io_reg : 8'bz;

    // ==========================================================
    // ECC Submodule Connections
    // ==========================================================
    wire [ECC_WIDTH-1:0] ecc_enc_out;
    wire [DATA_WIDTH-1:0] ecc_dec_out_data;
    wire ecc_corrected;
    wire ecc_uncorrectable;

    ftj_ecc_encoder ecc_encoder (
        .data_in(curr_wdata),
        .parity_out(ecc_enc_out)
    );

    ftj_ecc_decoder ecc_decoder (
        .data_in(latch_rdata[63:0]),
        .parity_in(latch_rdata[71:64]),
        .data_out(ecc_dec_out_data),
        .corrected(ecc_corrected),
        .uncorrectable(ecc_uncorrectable)
    );

    assign host_ecc_corrected_err     = ecc_corrected;
    assign host_ecc_uncorrectable_err = ecc_uncorrectable;

    // ==========================================================
    // Main Controller FSM
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= STATE_IDLE;
            init_done          <= 1'b0;
            init_ptr           <= 8'd0;
            pe_init_ptr        <= 10'd0;
            free_block_count   <= BLOCKS;
            
            axi_awready_reg    <= 1'b0;
            axi_wready_reg     <= 1'b0;
            axi_bvalid_reg     <= 1'b0;
            axi_bresp_reg      <= 2'b00;
            axi_arready_reg    <= 1'b0;
            axi_rvalid_reg     <= 1'b0;
            axi_rdata_reg      <= 64'd0;
            axi_rresp_reg      <= 2'b00;
            axi_rlast_reg      <= 1'b0;
            
            nand_cle_reg       <= 1'b0;
            nand_ale_reg       <= 1'b0;
            nand_re_n_reg      <= 1'b1;
            nand_we_n_reg      <= 1'b1;
            nand_ce_n_reg      <= 1'b1;
            nand_io_reg        <= 8'h00;
            nand_io_oe         <= 1'b0;
            nand_wait_cnt      <= 19'd0;
            
            burst_len_latch    <= 8'd0;
            burst_beat_cnt     <= 8'd0;
            burst_base_addr    <= 32'd0;
            
            curr_op            <= 1'b0;
            curr_pba           <= 32'd0;
            curr_wdata         <= 64'd0;
            latch_ecc          <= 8'd0;
            latch_rdata        <= 72'd0;
            
            gc_scan_ptr        <= 10'd0;
            gc_victim_block    <= 10'd0;
            min_gc_count       <= 8'hFF;
            
            wl_scan_ptr        <= 10'd0;
            wl_cold_victim     <= 32'd0;
            wl_hot_block       <= 32'd0;
            min_pe_count       <= 16'hFFFF;
            wl_needed          <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    axi_bvalid_reg <= 1'b0;
                    axi_rvalid_reg <= 1'b0;
                    axi_rlast_reg  <= 1'b0;
                    
                    if (!init_done) begin
                        ftl_l2p_map[init_ptr] <= {24'd0, init_ptr};
                        init_ptr <= init_ptr + 1'b1;
                        
                        pe_cycle_table[pe_init_ptr] <= 16'd0;
                        gc_valid_count[pe_init_ptr] <= 8'd0;
                        pe_init_ptr <= (pe_init_ptr == BLOCKS - 1) ? pe_init_ptr : pe_init_ptr + 1'b1;
                        
                        if (init_ptr == 8'hFF && pe_init_ptr == (BLOCKS - 1)) begin
                            init_done <= 1'b1;
                        end
                    end else if (free_block_count < GC_THRESHOLD) begin
                        state           <= STATE_GC_SELECT;
                        gc_scan_ptr     <= 10'd0;
                        gc_victim_block <= 10'd0;
                        min_gc_count    <= 8'hFF;
                    end else if (axi_awvalid && !axi_awready_reg) begin
                        axi_awready_reg <= 1'b1;
                        state           <= STATE_FETCH;
                    end else if (axi_arvalid && !axi_arready_reg) begin
                        axi_arready_reg <= 1'b1;
                        curr_op         <= 1'b0;
                        burst_base_addr <= axi_araddr;
                        burst_len_latch <= axi_arlen;
                        state           <= STATE_FTL_TRANSLATE;
                    end
                end

                STATE_FETCH: begin
                    burst_len_latch <= axi_awlen;
                    burst_base_addr <= axi_awaddr;
                    axi_awready_reg <= 1'b0;
                    axi_wready_reg  <= 1'b1;
                    curr_op         <= 1'b1;
                    burst_beat_cnt  <= 8'd0;
                    state           <= STATE_COALESCE;
                end

                STATE_COALESCE: begin
                    if (axi_wvalid && axi_wready_reg) begin
                        burst_beat_cnt <= burst_beat_cnt + 1'b1;
                        curr_wdata     <= axi_wdata;
                        if (axi_wlast) begin
                            axi_wready_reg <= 1'b0;
                            state          <= STATE_FTL_TRANSLATE;
                        end
                    end
                end

                STATE_FTL_TRANSLATE: begin
                    axi_arready_reg <= 1'b0;
                    curr_pba        <= ftl_l2p_map[burst_base_addr[7:0]];
                    if (curr_op == 1'b1) begin
                        state <= STATE_ECC_GEN;
                    end else begin
                        state <= STATE_PAGE_READ;
                    end
                end

                STATE_ECC_GEN: begin
                    latch_ecc <= ecc_enc_out;
                    state     <= STATE_PAGE_PROGRAM;
                end

                STATE_PAGE_PROGRAM: begin
                    nand_cle_reg  <= 1'b1;
                    nand_we_n_reg <= 1'b0;
                    nand_io_reg   <= 8'h80;
                    nand_io_oe    <= 1'b1;
                    nand_ce_n_reg <= 1'b0;
                    nand_wait_cnt <= 19'd30000;
                    
                    pe_cycle_table[curr_pba[9:0]] <= pe_cycle_table[curr_pba[9:0]] + 1'b1;
                    if (pe_cycle_table[curr_pba[9:0]] > TLC_MAX_PE) begin
                        wl_needed    <= 1'b1;
                        wl_hot_block <= curr_pba;
                    end else begin
                        wl_needed    <= 1'b0;
                    end
                    state <= STATE_PROG_WAIT;
                end

                STATE_PROG_WAIT: begin
                    nand_cle_reg  <= 1'b0;
                    nand_we_n_reg <= 1'b1;
                    nand_io_oe    <= 1'b0;
                    if (nand_wait_cnt > 0) begin
                        nand_wait_cnt <= nand_wait_cnt - 1'b1;
                    end else if (nand_rb_n == 1'b1) begin
                        if (wl_needed) begin
                            state          <= STATE_WL_REMAP;
                            wl_scan_ptr    <= 10'd0;
                            wl_cold_victim <= 32'd0;
                            min_pe_count   <= 16'hFFFF;
                        end else begin
                            state <= STATE_RESPOND;
                        end
                    end
                end

                STATE_PAGE_READ: begin
                    nand_cle_reg  <= 1'b1;
                    nand_we_n_reg <= 1'b0;
                    nand_io_reg   <= 8'h00;
                    nand_io_oe    <= 1'b1;
                    nand_ce_n_reg <= 1'b0;
                    nand_wait_cnt <= 19'd2500;
                    state         <= STATE_READ_WAIT;
                end

                STATE_READ_WAIT: begin
                    nand_cle_reg  <= 1'b0;
                    nand_we_n_reg <= 1'b1;
                    nand_io_oe    <= 1'b0;
                    if (nand_wait_cnt > 0) begin
                        nand_wait_cnt <= nand_wait_cnt - 1'b1;
                    end else if (nand_rb_n == 1'b1) begin
                        latch_rdata <= {8'd0, 56'd0, nand_io};
                        state       <= STATE_AFE_SENSE;
                    end
                end

                STATE_AFE_SENSE: begin
                    axi_rvalid_reg <= 1'b1;
                    axi_rdata_reg  <= ecc_dec_out_data;
                    axi_rlast_reg  <= 1'b1;
                    state          <= STATE_RESPOND;
                end

                STATE_GC_SELECT: begin
                    if (gc_scan_ptr == 0) begin
                        min_gc_count    <= gc_valid_count[0];
                        gc_victim_block <= 0;
                        gc_scan_ptr     <= 1;
                    end else begin
                        if (gc_valid_count[gc_scan_ptr] < min_gc_count) begin
                            min_gc_count    <= gc_valid_count[gc_scan_ptr];
                            gc_victim_block <= gc_scan_ptr;
                        end
                        gc_scan_ptr <= gc_scan_ptr + 1'b1;
                        if (gc_scan_ptr == BLOCKS - 1) begin
                            state <= STATE_GC_COPY;
                        end
                    end
                end

                STATE_GC_COPY: begin
                    gc_valid_count[gc_victim_block] <= 8'd0;
                    state <= STATE_BLOCK_ERASE;
                end

                STATE_BLOCK_ERASE: begin
                    nand_cle_reg     <= 1'b1;
                    nand_we_n_reg    <= 1'b0;
                    nand_io_reg      <= 8'h60;
                    nand_io_oe       <= 1'b1;
                    nand_ce_n_reg    <= 1'b0;
                    nand_wait_cnt    <= 19'd300000;
                    free_block_count <= free_block_count + 1'b1;
                    state            <= STATE_ERASE_WAIT;
                end

                STATE_ERASE_WAIT: begin
                    nand_cle_reg  <= 1'b0;
                    nand_we_n_reg <= 1'b1;
                    nand_io_oe    <= 1'b0;
                    if (nand_wait_cnt > 0) begin
                        nand_wait_cnt <= nand_wait_cnt - 1'b1;
                    end else if (nand_rb_n == 1'b1) begin
                        nand_ce_n_reg <= 1'b1;
                        state         <= STATE_IDLE;
                    end
                end

                STATE_WL_REMAP: begin
                    if (wl_scan_ptr == 0) begin
                        min_pe_count   <= pe_cycle_table[0];
                        wl_cold_victim <= 0;
                        wl_scan_ptr    <= 1;
                    end else begin
                        if (pe_cycle_table[wl_scan_ptr] < min_pe_count) begin
                            min_pe_count   <= pe_cycle_table[wl_scan_ptr];
                            wl_cold_victim <= wl_scan_ptr;
                        end
                        wl_scan_ptr <= wl_scan_ptr + 1'b1;
                        if (wl_scan_ptr == BLOCKS - 1) begin
                            ftl_l2p_map[wl_cold_victim[7:0]] <= wl_hot_block;
                            state <= STATE_RESPOND;
                        end
                    end
                end

                STATE_RESPOND: begin
                    nand_ce_n_reg <= 1'b1;
                    if (curr_op == 1'b1) begin
                        axi_bvalid_reg <= 1'b1;
                        axi_bresp_reg  <= 2'b00;
                        if (axi_bready && axi_bvalid_reg) begin
                            axi_bvalid_reg <= 1'b0;
                            state          <= STATE_IDLE;
                        end
                    end else begin
                        if (axi_rready && axi_rvalid_reg) begin
                            axi_rvalid_reg <= 1'b0;
                            axi_rlast_reg  <= 1'b0;
                            state          <= STATE_IDLE;
                        end else if (!axi_rvalid_reg) begin
                            state <= STATE_IDLE;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule


// =================================================================
// Submodule: Hamming SECDED (72, 64) Encoder
// =================================================================
module ftj_ecc_encoder (
    input  wire [63:0] data_in,
    output wire [7:0]  parity_out
);
    // Simple parity trees for SECDED parity bits (p0 to p6)
    assign parity_out[0] = ^(data_in & 64'h5555555555555555);
    assign parity_out[1] = ^(data_in & 64'h3333333333333333);
    assign parity_out[2] = ^(data_in & 64'h0F0F0F0F0F0F0F0F);
    assign parity_out[3] = ^(data_in & 64'h00FF00FF00FF00FF);
    assign parity_out[4] = ^(data_in & 64'h0000FFFF0000FFFF);
    assign parity_out[5] = ^(data_in & 64'h00000000FFFFFFFF);
    assign parity_out[6] = ^data_in; // Parity over bits
    assign parity_out[7] = ^data_in ^ ^parity_out[6:0]; // Overall parity bit (SECDED)
endmodule

// =================================================================
// Submodule: Hamming SECDED (72, 64) Decoder
// =================================================================
module ftj_ecc_decoder (
    input  wire [63:0] data_in,
    input  wire [7:0]  parity_in,
    output reg  [63:0] data_out,
    output reg         corrected,
    output reg         uncorrectable
);
    wire [7:0] calc_parity;
    ftj_ecc_encoder encoder_inst (
        .data_in(data_in),
        .parity_out(calc_parity)
    );

    wire [7:0] syndrome = calc_parity ^ parity_in;
    wire syndrome_zero = (syndrome[6:0] == 7'd0);
    wire parity_error  = syndrome[7];

    always @(*) begin
        data_out      = data_in;
        corrected     = 1'b0;
        uncorrectable = 1'b0;

        if (syndrome != 8'd0) begin
            if (parity_error) begin
                // Single-bit error detected: correct it
                corrected = 1'b1;
                // Correct single-bit position mapping
                if (syndrome[6:0] <= 7'd64) begin
                    data_out[syndrome[6:0]-1] = ~data_in[syndrome[6:0]-1];
                end
            end else if (!syndrome_zero) begin
                // Double-bit error detected: uncorrectable
                uncorrectable = 1'b1;
            end
        end
    end
endmodule

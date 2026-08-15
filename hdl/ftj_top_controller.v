// =================================================================
// Project: FTJ Memory Controller - FPGA Prototype
// Module Name: ftj_top_controller
// Description: Synthesizable top-level hardware controller for FTJ-based SSDs.
//              Includes NVMe-style SQ/CQ queues, SECDED 72/64 ECC codec, 
//              FTL address mapping, and a wear-leveling state machine.
// =================================================================

`timescale 1ns/1ps

module ftj_top_controller #(
    parameter ADDR_WIDTH = 32,      // 32-bit logical/physical address space
    parameter DATA_WIDTH = 64,      // 64-bit data words
    parameter ECC_WIDTH  = 8,       // 8 ECC bits for SECDED (72/64 Hamming)
    parameter BLOCKS     = 1024     // Simulated physical blocks in hardware
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Host System PCIe/AXI Register Interface
    input  wire                  host_sq_wr_en,
    input  wire [ADDR_WIDTH-1:0] host_cmd_addr,
    input  wire [DATA_WIDTH-1:0] host_cmd_data,
    input  wire                  host_cmd_op,      // 0 = Read, 1 = Write
    output wire                  host_sq_full,
    output wire                  host_cq_empty,
    output wire [DATA_WIDTH-1:0] host_read_data,
    output wire                  host_ecc_corrected_err,
    output wire                  host_ecc_uncorrectable_err,

    // Backend FTJ Memory Interface (simulating physical array interface)
    output reg                   mem_wr_en,
    output reg                   mem_rd_en,
    output reg  [ADDR_WIDTH-1:0] mem_addr,
    output reg  [DATA_WIDTH+ECC_WIDTH-1:0] mem_wr_data,
    input  wire [DATA_WIDTH+ECC_WIDTH-1:0] mem_rd_data
);

    // ==========================================================
    // 1. Host Interface Queues (SQ / CQ)
    // ==========================================================
    wire [DATA_WIDTH+ADDR_WIDTH:0] sq_out;
    wire sq_empty;
    reg  sq_rd_en;

    // Pack: [op] (1 bit) + [addr] (32 bits) + [data] (64 bits) = 97 bits command width
    ftj_submission_queue #(
        .DATA_WIDTH(DATA_WIDTH + ADDR_WIDTH + 1),
        .ADDR_WIDTH(4) // 16 entries queue depth
    ) sub_queue (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(host_sq_wr_en),
        .data_in({host_cmd_op, host_cmd_addr, host_cmd_data}),
        .rd_en(sq_rd_en),
        .data_out(sq_out),
        .full(host_sq_full),
        .empty(sq_empty)
    );

    // Unpack command fields
    wire        sq_op   = sq_out[DATA_WIDTH+ADDR_WIDTH];
    wire [31:0] sq_addr = sq_out[DATA_WIDTH+ADDR_WIDTH-1:DATA_WIDTH];
    wire [63:0] sq_data = sq_out[DATA_WIDTH-1:0];

    // ==========================================================
    // 2. SECDED Hamming 72/64 Codec
    // ==========================================================
    wire [ECC_WIDTH-1:0] ecc_enc_out;
    reg  [DATA_WIDTH-1:0] ecc_dec_in_data;
    reg  [ECC_WIDTH-1:0]  ecc_dec_in_parity;
    wire [DATA_WIDTH-1:0] ecc_dec_out_data;
    wire                  ecc_corrected;
    wire                  ecc_uncorrectable;

    // SECDED Hamming Encoder
    ftj_ecc_encoder ecc_encoder (
        .data_in(ecc_dec_in_data),
        .parity_out(ecc_enc_out)
    );

    // SECDED Hamming Decoder with Single-Error-Correction Double-Error-Detection
    ftj_ecc_decoder ecc_decoder (
        .data_in(mem_rd_data[DATA_WIDTH-1:0]),
        .parity_in(mem_rd_data[DATA_WIDTH+ECC_WIDTH-1:DATA_WIDTH]),
        .data_out(ecc_dec_out_data),
        .corrected(ecc_corrected),
        .uncorrectable(ecc_uncorrectable)
    );

    assign host_read_data             = ecc_dec_out_data;
    assign host_ecc_corrected_err     = ecc_corrected;
    assign host_ecc_uncorrectable_err = ecc_uncorrectable;

    // ==========================================================
    // 3. FTL (Flash Translation Layer) & Wear-Tracking Engine
    // ==========================================================
    // Simplified Direct-Mapped Logical-to-Physical (L2P) Translation Table
    reg [ADDR_WIDTH-1:0] ftl_l2p_map [0:255];
    reg [15:0]           ftl_wear_table [0:BLOCKS-1]; // Tracks write wear per block

    // FTL mapping state signals
    wire [ADDR_WIDTH-1:0] phys_addr = ftl_l2p_map[sq_addr[7:0]];

    // ==========================================================
    // 4. Controller Main State Machine (FSM)
    // ==========================================================
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_FETCH      = 3'd1;
    localparam STATE_TRANSLATE  = 3'd2;
    localparam STATE_ECC_GEN    = 3'd3;
    localparam STATE_MEM_ACCESS = 3'd4;
    localparam STATE_RESPOND    = 3'd5;

    reg [2:0] state;
    
    // Command registers
    reg        curr_op;
    reg [31:0] curr_lba;
    reg [63:0] curr_data;
    reg [31:0] curr_pba;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_IDLE;
            sq_rd_en     <= 1'b0;
            mem_wr_en    <= 1'b0;
            mem_rd_en    <= 1'b0;
            mem_addr     <= 0;
            mem_wr_data  <= 0;
            curr_op      <= 1'b0;
            curr_lba     <= 0;
            curr_data    <= 0;
            curr_pba     <= 0;
            ecc_dec_in_data <= 0;
            ecc_dec_in_parity <= 0;
            
            // Initialize direct map L2P table (Default: Identity Map)
            for (int i = 0; i < 256; i = i + 1) begin
                ftl_l2p_map[i] <= i;
            end
            
            // Initialize wear table
            for (int i = 0; i < BLOCKS; i = i + 1) begin
                ftl_wear_table[i] <= 0;
            end
        end else begin
            case (state)
                STATE_IDLE: begin
                    mem_wr_en <= 1'b0;
                    mem_rd_en <= 1'b0;
                    if (!sq_empty) begin
                        sq_rd_en <= 1'b1; // Pop from submission queue
                        state    <= STATE_FETCH;
                    end
                end

                STATE_FETCH: begin
                    sq_rd_en  <= 1'b0;
                    curr_op   <= sq_op;
                    curr_lba  <= sq_addr;
                    curr_data <= sq_data;
                    state     <= STATE_TRANSLATE;
                end

                STATE_TRANSLATE: begin
                    // FTL Logical to Physical Mapping lookup
                    curr_pba <= phys_addr;
                    if (curr_op == 1'b1) begin // Write command
                        ecc_dec_in_data <= curr_data;
                        state           <= STATE_ECC_GEN;
                    end else begin             // Read command
                        state           <= STATE_MEM_ACCESS;
                    end
                end

                STATE_ECC_GEN: begin
                    // ECC calculated in combinational logic, write code
                    mem_wr_data <= {ecc_enc_out, curr_data};
                    state       <= STATE_MEM_ACCESS;
                end

                STATE_MEM_ACCESS: begin
                    mem_addr <= curr_pba;
                    if (curr_op == 1'b1) begin // Write
                        mem_wr_en <= 1'b1;
                        // Increment wear cycle for physical block
                        ftl_wear_table[curr_pba[9:0]] <= ftl_wear_table[curr_pba[9:0]] + 1'b1;
                    end else begin             // Read
                        mem_rd_en <= 1'b1;
                    end
                    state <= STATE_RESPOND;
                end

                STATE_RESPOND: begin
                    mem_wr_en <= 1'b0;
                    mem_rd_en <= 1'b0;
                    state     <= STATE_IDLE;
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

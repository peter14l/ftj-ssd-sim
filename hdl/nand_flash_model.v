// nand_flash_model.v
// Synthesizable 3D NAND Flash Behavioral Model (ONFI 4.2 subset)
// Supports: Page Program, Page Read, Block Erase
// Timing: tPROG=30000cy, tBERS=300000cy, tREAD=2500cy (@ 100MHz)

`timescale 1ns/1ps

module nand_flash_model #(
    parameter BLOCKS        = 1024,
    parameter PAGES_PER_BLK = 256,
    parameter PAGE_BYTES    = 4096,
    parameter TPROG_CYCLES  = 30000,
    parameter TBERS_CYCLES  = 300000,
    parameter TREAD_CYCLES  = 2500
)(
    input  wire       clk,
    input  wire       rst_n,
    inout  wire [7:0] nand_io,
    input  wire       nand_cle,
    input  wire       nand_ale,
    input  wire       nand_re_n,
    input  wire       nand_we_n,
    input  wire       nand_ce_n,
    output reg        nand_rb_n
);

    localparam NAND_IDLE       = 4'd0;
    localparam NAND_CMD_LATCH  = 4'd1;
    localparam NAND_ADDR_LATCH = 4'd2;
    localparam NAND_DATA_IN    = 4'd3;
    localparam NAND_BUSY_PROG  = 4'd4;
    localparam NAND_BUSY_READ  = 4'd5;
    localparam NAND_BUSY_ERASE = 4'd6;
    localparam NAND_DATA_OUT   = 4'd7;
    localparam NAND_STATUS     = 4'd8;
    localparam NAND_INIT       = 4'd9;

    reg [3:0]  state;
    reg [7:0]  page_buf [0:PAGE_BYTES-1];
    reg [15:0] block_pe_count [0:BLOCKS-1];
    
    reg [7:0]  col_addr_lo;
    reg [7:0]  col_addr_hi;
    reg [7:0]  row_addr_lo;
    reg [7:0]  row_addr_mid;
    reg [7:0]  row_addr_hi;
    
    reg [2:0]  addr_cyc;
    reg [12:0] page_idx;
    
    reg [18:0] wait_cnt;
    reg        nand_io_oe;
    reg [7:0]  nand_io_out;
    
    reg        we_n_d1;
    reg        re_n_d1;
    
    reg [12:0] init_ptr_page;
    reg [9:0]  init_ptr_blk;
    reg        init_done;

    assign nand_io = nand_io_oe ? nand_io_out : 8'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= NAND_INIT;
            nand_rb_n     <= 1'b1;
            nand_io_oe    <= 1'b0;
            nand_io_out   <= 8'd0;
            we_n_d1       <= 1'b1;
            re_n_d1       <= 1'b1;
            wait_cnt      <= 19'd0;
            init_ptr_page <= 13'd0;
            init_ptr_blk  <= 10'd0;
            init_done     <= 1'b0;
            addr_cyc      <= 3'd0;
            page_idx      <= 13'd0;
            col_addr_lo   <= 8'd0;
            col_addr_hi   <= 8'd0;
            row_addr_lo   <= 8'd0;
            row_addr_mid  <= 8'd0;
            row_addr_hi   <= 8'd0;
        end else begin
            we_n_d1 <= nand_we_n;
            re_n_d1 <= nand_re_n;
            
            case (state)
                NAND_INIT: begin
                    page_buf[init_ptr_page] <= 8'hFF;
                    init_ptr_page <= init_ptr_page + 1'b1;
                    
                    if (init_ptr_blk < BLOCKS) begin
                        block_pe_count[init_ptr_blk] <= 16'd0;
                        init_ptr_blk <= init_ptr_blk + 1'b1;
                    end
                    
                    if (init_ptr_page == (PAGE_BYTES - 1) && init_ptr_blk == BLOCKS) begin
                        init_done <= 1'b1;
                        state     <= NAND_IDLE;
                    end
                end
                
                NAND_IDLE: begin
                    nand_io_oe <= 1'b0;
                    if (!nand_ce_n) begin
                        if (nand_we_n && !we_n_d1) begin // Rising edge of WE_n
                            if (nand_cle) begin
                                case (nand_io)
                                    8'h80: begin 
                                        state <= NAND_DATA_IN; 
                                        addr_cyc <= 0; 
                                        page_idx <= 0; 
                                    end
                                    8'h10: begin 
                                        state <= NAND_BUSY_PROG; 
                                        nand_rb_n <= 1'b0; 
                                        wait_cnt <= TPROG_CYCLES; 
                                        block_pe_count[row_addr_mid] <= block_pe_count[row_addr_mid] + 1'b1; 
                                    end
                                    8'h00: begin 
                                        state <= NAND_ADDR_LATCH; 
                                        addr_cyc <= 0; 
                                    end
                                    8'h30: begin 
                                        state <= NAND_BUSY_READ; 
                                        nand_rb_n <= 1'b0; 
                                        wait_cnt <= TREAD_CYCLES; 
                                    end
                                    8'h60: begin 
                                        state <= NAND_ADDR_LATCH; 
                                        addr_cyc <= 0; 
                                    end
                                    8'hD0: begin 
                                        state <= NAND_BUSY_ERASE; 
                                        nand_rb_n <= 1'b0; 
                                        wait_cnt <= TBERS_CYCLES; 
                                    end
                                    8'h70: begin 
                                        state <= NAND_STATUS; 
                                    end
                                    default: state <= NAND_IDLE;
                                endcase
                            end else if (nand_ale) begin
                                state <= NAND_ADDR_LATCH;
                            end
                        end
                    end
                end
                
                NAND_ADDR_LATCH: begin
                    if (!nand_ce_n && nand_we_n && !we_n_d1) begin
                        if (nand_cle) begin
                            case (nand_io)
                                8'h30: begin 
                                    state <= NAND_BUSY_READ; 
                                    nand_rb_n <= 1'b0; 
                                    wait_cnt <= TREAD_CYCLES; 
                                end
                                8'hD0: begin 
                                    state <= NAND_BUSY_ERASE; 
                                    nand_rb_n <= 1'b0; 
                                    wait_cnt <= TBERS_CYCLES; 
                                end
                            endcase
                        end else if (nand_ale) begin
                            case (addr_cyc)
                                0: col_addr_lo  <= nand_io;
                                1: col_addr_hi  <= nand_io;
                                2: row_addr_lo  <= nand_io;
                                3: row_addr_mid <= nand_io;
                                4: row_addr_hi  <= nand_io;
                            endcase
                            addr_cyc <= addr_cyc + 1'b1;
                        end else if (!nand_ale && !nand_cle) begin
                            state <= NAND_DATA_IN;
                        end
                    end
                end
                
                NAND_DATA_IN: begin
                    if (!nand_ce_n && nand_we_n && !we_n_d1) begin
                        if (nand_cle) begin
                            case (nand_io)
                                8'h10: begin 
                                    state <= NAND_BUSY_PROG; 
                                    nand_rb_n <= 1'b0; 
                                    wait_cnt <= TPROG_CYCLES; 
                                    block_pe_count[row_addr_mid] <= block_pe_count[row_addr_mid] + 1'b1; 
                                end
                            endcase
                        end else if (nand_ale) begin
                            case (addr_cyc)
                                0: col_addr_lo  <= nand_io;
                                1: col_addr_hi  <= nand_io;
                                2: row_addr_lo  <= nand_io;
                                3: row_addr_mid <= nand_io;
                                4: row_addr_hi  <= nand_io;
                            endcase
                            addr_cyc <= addr_cyc + 1'b1;
                        end else begin
                            page_buf[page_idx] <= nand_io;
                            if (page_idx < PAGE_BYTES - 1) begin
                                page_idx <= page_idx + 1'b1;
                            end
                        end
                    end
                end
                
                NAND_BUSY_PROG: begin
                    if (wait_cnt > 0) begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end else begin
                        nand_rb_n <= 1'b1;
                        state     <= NAND_IDLE;
                    end
                end
                
                NAND_BUSY_READ: begin
                    if (wait_cnt > 0) begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end else begin
                        nand_rb_n <= 1'b1;
                        page_idx  <= {col_addr_hi[4:0], col_addr_lo};
                        state     <= NAND_DATA_OUT;
                    end
                end
                
                NAND_BUSY_ERASE: begin
                    if (wait_cnt > 0) begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end else begin
                        nand_rb_n <= 1'b1;
                        state     <= NAND_IDLE;
                    end
                end
                
                NAND_DATA_OUT: begin
                    if (!nand_ce_n) begin
                        if (nand_re_n && !re_n_d1) begin
                            if (page_idx < PAGE_BYTES - 1) begin
                                page_idx <= page_idx + 1'b1;
                            end
                        end else if (!nand_re_n) begin
                            nand_io_oe  <= 1'b1;
                            nand_io_out <= page_buf[page_idx];
                        end else begin
                            nand_io_oe <= 1'b0;
                        end
                        
                        if (nand_we_n && !we_n_d1 && nand_cle) begin
                            nand_io_oe <= 1'b0;
                            if (nand_io == 8'h70) begin
                                state <= NAND_STATUS;
                            end else begin
                                state <= NAND_IDLE;
                            end
                        end
                    end else begin
                        nand_io_oe <= 1'b0;
                    end
                end
                
                NAND_STATUS: begin
                    if (!nand_ce_n && !nand_re_n) begin
                        nand_io_oe  <= 1'b1;
                        nand_io_out <= 8'he0;
                    end else begin
                        nand_io_oe <= 1'b0;
                    end
                    
                    if (!nand_ce_n && nand_we_n && !we_n_d1 && nand_cle) begin
                        nand_io_oe <= 1'b0;
                        if (nand_io == 8'h00) begin
                            state <= NAND_IDLE;
                        end
                    end
                end
                
                default: state <= NAND_IDLE;
            endcase
        end
    end
endmodule

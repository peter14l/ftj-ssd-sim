// =================================================================
// Project: FTJ Memory Controller - FPGA Prototype
// Module Name: ftj_submission_queue (FIFO Circular Buffer)
// Description: Implements a hardware-level queue that accepts incoming
//              read/write requests from the host CPU.
// =================================================================

`timescale 1ns/1ps

module ftj_submission_queue #(
    parameter DATA_WIDTH = 64, // Width of each request (e.g. 64 bits for address & command details)
    parameter ADDR_WIDTH = 4   // 4-bit address size gives us a Queue Depth of 2^4 = 16 slots
)(
    input  wire                  clk,       // Main clock signal (ticks millions of times per second)
    input  wire                  rst_n,     // Reset signal (active low - resets the hardware pointers to zero)
    
    // Write Interface (Host CPU submits a new request)
    input  wire                  wr_en,     // Write Enable (Host pulls this high to push data)
    input  wire [DATA_WIDTH-1:0] data_in,   // The incoming command data from the host CPU
    
    // Read Interface (FTJ Memory Engine pops and processes the request)
    input  wire                  rd_en,     // Read Enable (Controller pulls this high to pop data)
    output reg  [DATA_WIDTH-1:0] data_out,  // The outgoing command data to be executed
    
    // Queue Status Flags
    output wire                  full,      // High if the queue is full (host must wait)
    output wire                  empty      // High if the queue is empty (no jobs to process)
);

    // Local registers (transistors on the FPGA) to store pointers and status
    reg [ADDR_WIDTH-1:0] wr_ptr;      // Points to where the next incoming command will be written
    reg [ADDR_WIDTH-1:0] rd_ptr;      // Points to the next command waiting to be processed
    reg                  is_full;     // Internal flag to track if the queue is full

    // Storage array (registers representing the queue slots)
    // 16 slots, each holding DATA_WIDTH bits of data
    reg [DATA_WIDTH-1:0] queue_mem [0:(1<<ADDR_WIDTH)-1];

    // Combinational status assignments
    assign empty = (wr_ptr == rd_ptr) && !is_full;
    assign full  = is_full;

    // Sequential Hardware Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // When reset button is pressed: reset all pointers to zero
            wr_ptr   <= 0;
            rd_ptr   <= 0;
            is_full  <= 0;
            data_out <= 0;
        end else begin
            
            // --- WRITE OPERATION ---
            // If the host wants to write and we aren't full:
            if (wr_en && !full) begin
                queue_mem[wr_ptr] <= data_in; // Store data in current slot
                wr_ptr <= wr_ptr + 1;         // Advance write pointer (automatically wraps around because it's 4-bit)
            end

            // --- READ OPERATION ---
            // If the engine wants to read and we aren't empty:
            if (rd_en && !empty) begin
                data_out <= queue_mem[rd_ptr]; // Fetch data from current slot
                rd_ptr <= rd_ptr + 1;          // Advance read pointer
            end

            // --- FULL FLAG TRACKING ---
            // Check if we are full: if the pointers meet and we just wrote, we are full
            if (wr_en && !full && (wr_ptr + 1'b1 == rd_ptr)) begin
                is_full <= 1'b1;
            end
            
            // If we read, we are guaranteed not to be full anymore
            if (rd_en && is_full) begin
                is_full <= 1'b0;
            end

        end
    end

endmodule

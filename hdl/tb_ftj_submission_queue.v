// =================================================================
// Project: FTJ Memory Controller - FPGA Testbench
// Module Name: tb_ftj_submission_queue
// Description: Verilog testbench to simulate clock cycles and verify
//              queue functionality (Push/Pop/Full/Empty behavior).
// =================================================================

`timescale 1ns/1ps

module tb_ftj_submission_queue;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg wr_en;
    reg [63:0] data_in;
    reg rd_en;
    
    wire [63:0] data_out;
    wire full;
    wire empty;

    // Instantiate the Unit Under Test (UUT)
    ftj_submission_queue #(
        .DATA_WIDTH(64),
        .ADDR_WIDTH(4) // 16 slots
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .data_in(data_in),
        .rd_en(rd_en),
        .data_out(data_out),
        .full(full),
        .empty(empty)
    );

    // Clock Generator (Creates a clock ticking every 10 nanoseconds)
    always #5 clk = ~clk;

    // Test Sequence
    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        wr_en = 0;
        data_in = 0;
        rd_en = 0;

        // Display logging
        $monitor("Time=%0t ns | Reset=%b | Wr=%b DataIn=%h | Rd=%b DataOut=%h | Full=%b Empty=%b", 
                 $time, rst_n, wr_en, data_in, rd_en, data_out, full, empty);

        // 1. Release reset after 20ns
        #20;
        rst_n = 1;
        #10;

        // 2. Submit three commands to the queue
        $display("\n--- Submitting 3 Requests ---");
        Push(64'hAAAA_BBBB_0000_0001);
        Push(64'hAAAA_BBBB_0000_0002);
        Push(64'hAAAA_BBBB_0000_0003);

        // 3. Pop and read them back
        $display("\n--- Popping 2 Requests ---");
        Pop();
        Pop();

        // 4. Fill the queue until it is full (capacity is 16 slots)
        $display("\n--- Filling Queue to Capacity ---");
        Push(64'hC0DE_0001);
        Push(64'hC0DE_0002);
        Push(64'hC0DE_0003);
        Push(64'hC0DE_0004);
        Push(64'hC0DE_0005);
        Push(64'hC0DE_0006);
        Push(64'hC0DE_0007);
        Push(64'hC0DE_0008);
        Push(64'hC0DE_0009);
        Push(64'hC0DE_0010);
        Push(64'hC0DE_0011);
        Push(64'hC0DE_0012);
        Push(64'hC0DE_0013);
        Push(64'hC0DE_0014); // Queue should be full now

        // Try to push one more (should fail / ignore because full)
        Push(64'hC0DE_DEAD);

        // 5. Empty the queue entirely
        $display("\n--- Emptying the Queue ---");
        while (!empty) begin
            Pop();
        end

        #40;
        $display("\n--- Simulation Completed ---");
        $finish;
    end

    // Helper Tasks for writing stimulus
    task Push(input [63:0] val);
        begin
            @(posedge clk);
            wr_en = 1;
            data_in = val;
            @(posedge clk);
            wr_en = 0;
        end
    endtask

    task Pop();
        begin
            @(posedge clk);
            rd_en = 1;
            @(posedge clk);
            rd_en = 0;
        end
    endtask

endmodule

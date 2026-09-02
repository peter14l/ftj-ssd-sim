`ifndef UVM_TB_TOP_SV
`define UVM_TB_TOP_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "nvme_flash_if.sv"
`include "controller_transaction.sv"
`include "controller_sequencer.sv"
`include "controller_sequence.sv"
`include "controller_driver.sv"
`include "controller_monitor.sv"
`include "controller_scoreboard.sv"
`include "controller_agent.sv"
`include "controller_env.sv"

// ============================================================
// Base Test
// ============================================================
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    controller_env env;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = controller_env::type_id::create("env", this);
    endfunction
endclass

// ============================================================
// AI Checkpoint Test
// ============================================================
class ai_checkpoint_test extends base_test;
    `uvm_component_utils(ai_checkpoint_test)

    function new(string name = "ai_checkpoint_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        ai_checkpoint_seq seq;
        phase.raise_objection(this);
        seq = ai_checkpoint_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        phase.drop_objection(this);
    endtask
endclass

// ============================================================
// KV Cache Update Test
// ============================================================
class kv_cache_update_test extends base_test;
    `uvm_component_utils(kv_cache_update_test)

    function new(string name = "kv_cache_update_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        kv_cache_update_seq seq;
        phase.raise_objection(this);
        seq = kv_cache_update_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        phase.drop_objection(this);
    endtask
endclass

// synthesis translate_off

// ============================================================
// Top-Level Module
// ============================================================
module uvm_tb_top;
    logic clk;
    logic rst_n;

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    // Reset Generation
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end

    // Interface Instantiation
    nvme_flash_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .ID_WIDTH(4)
    ) vif (
        .clk(clk),
        .rst_n(rst_n)
    );

    // DUT Instantiation
    // Note: ftj_top_controller must be compiled alongside the testbench.
    ftj_top_controller #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .ECC_WIDTH(8),
        .BLOCKS(1024),
        .PAGES_PER_BLOCK(256),
        .TLC_MAX_PE(3000),
        .GC_THRESHOLD(100)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4 Write Address Channel
        .axi_awvalid(vif.axi_awvalid),
        .axi_awready(vif.axi_awready),
        .axi_awaddr(vif.axi_awaddr),
        .axi_awlen(vif.axi_awlen),
        .axi_awsize(vif.axi_awsize),
        .axi_awburst(vif.axi_awburst),
        .axi_awid(vif.axi_awid),
        
        // AXI4 Write Data Channel
        .axi_wvalid(vif.axi_wvalid),
        .axi_wready(vif.axi_wready),
        .axi_wdata(vif.axi_wdata),
        .axi_wstrb(vif.axi_wstrb),
        .axi_wlast(vif.axi_wlast),
        
        // AXI4 Write Response Channel
        .axi_bvalid(vif.axi_bvalid),
        .axi_bready(vif.axi_bready),
        .axi_bresp(vif.axi_bresp),
        .axi_bid(vif.axi_bid),
        
        // AXI4 Read Address Channel
        .axi_arvalid(vif.axi_arvalid),
        .axi_arready(vif.axi_arready),
        .axi_araddr(vif.axi_araddr),
        .axi_arlen(vif.axi_arlen),
        .axi_arsize(vif.axi_arsize),
        .axi_arburst(vif.axi_arburst),
        .axi_arid(vif.axi_arid),
        
        // AXI4 Read Data Channel
        .axi_rvalid(vif.axi_rvalid),
        .axi_rready(vif.axi_rready),
        .axi_rdata(vif.axi_rdata),
        .axi_rresp(vif.axi_rresp),
        .axi_rlast(vif.axi_rlast),
        .axi_rid(vif.axi_rid),

        // NAND Flash Parallel Bus
        // TB tie-offs and monitors
        .nand_io(8'hFF), // tie to 8'hFF for model-less sim
        .nand_cle(vif.nand_cle),
        .nand_ale(vif.nand_ale),
        .nand_re_n(vif.nand_re_n),
        .nand_we_n(vif.nand_we_n),
        .nand_ce_n(vif.nand_ce_n),
        .nand_rb_n(1'b1), // drive 1'b1 from tb for simulation
        
        // ECC Status
        .host_ecc_corrected_err(vif.host_ecc_corrected),
        .host_ecc_uncorrectable_err(vif.host_ecc_uncorrectable)
    );

    // Initial Block for UVM execution
    initial begin
        uvm_config_db #(virtual nvme_flash_if)::set(null, "*", "vif", vif);
        run_test();
    end

endmodule
// synthesis translate_on
`endif

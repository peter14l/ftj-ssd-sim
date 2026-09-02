`ifndef CONTROLLER_AGENT_SV
`define CONTROLLER_AGENT_SV

class controller_agent extends uvm_agent;
    `uvm_component_utils(controller_agent)

    controller_driver     drv;
    controller_monitor    mon;
    controller_sequencer  sqr;

    uvm_analysis_port #(controller_transaction) ap;

    function new(string name = "controller_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap  = new("ap", this);
        sqr = controller_sequencer::type_id::create("sqr", this);
        drv = controller_driver::type_id::create("drv", this);
        mon = controller_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
        mon.ap.connect(ap);
    endfunction

endclass : controller_agent

`endif

`ifndef CONTROLLER_SEQUENCER_SV
`define CONTROLLER_SEQUENCER_SV

class controller_sequencer extends uvm_sequencer #(controller_transaction);
    `uvm_component_utils(controller_sequencer)

    function new(string name = "controller_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : controller_sequencer

`endif

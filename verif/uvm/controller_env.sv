`ifndef CONTROLLER_ENV_SV
`define CONTROLLER_ENV_SV

class controller_env extends uvm_env;
    `uvm_component_utils(controller_env)

    controller_agent      agt;
    controller_scoreboard sb;

    function new(string name = "controller_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = controller_agent::type_id::create("agt", this);
        sb  = controller_scoreboard::type_id::create("sb",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.ap.connect(sb.analysis_export);
    endfunction

endclass : controller_env

`endif

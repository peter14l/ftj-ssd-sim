`ifndef CONTROLLER_MONITOR_SV
`define CONTROLLER_MONITOR_SV

class controller_monitor extends uvm_monitor;
    `uvm_component_utils(controller_monitor)

    virtual nvme_flash_if.monitor_mp vif;
    uvm_analysis_port #(controller_transaction) ap;

    // Coverage tracking
    int unsigned write_count;
    int unsigned read_count;
    int unsigned ecc_corrected_count;
    int unsigned ecc_uncorrectable_count;

    function new(string name = "controller_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual nvme_flash_if)::get(this, "", "vif", vif))
            `uvm_fatal("CFG", "controller_monitor: virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            collect_write_transaction();
        end
    endtask

    task collect_write_transaction();
        controller_transaction txn;
        txn = controller_transaction::type_id::create("mon_txn");

        // Detect write address phase
        do @(vif.monitor_cb); while (!vif.monitor_cb.axi_awvalid || !vif.monitor_cb.axi_awready);
        txn.address   = vif.monitor_cb.axi_awaddr;
        txn.burst_len = vif.monitor_cb.axi_awlen;
        txn.cmd_type  = 1'b1;

        // Collect write data beats
        txn.payload = new[txn.burst_len + 1];
        for (int beat = 0; beat <= txn.burst_len; beat++) begin
            do @(vif.monitor_cb); while (!vif.monitor_cb.axi_wvalid || !vif.monitor_cb.axi_wready);
            txn.payload[beat] = vif.monitor_cb.axi_wdata;
            txn.wstrb         = vif.monitor_cb.axi_wstrb;
            if (vif.monitor_cb.axi_wlast) break;
        end

        // Check ECC status on next clock
        @(vif.monitor_cb);
        if (vif.monitor_cb.host_ecc_corrected) begin
            ecc_corrected_count++;
            `uvm_info("MON", "ECC single-bit correction observed", UVM_MEDIUM)
        end
        if (vif.monitor_cb.host_ecc_uncorrectable) begin
            ecc_uncorrectable_count++;
            `uvm_error("MON", "ECC uncorrectable error observed!")
        end

        write_count++;
        `uvm_info("MON", $sformatf("Captured write txn: addr=0x%08h beats=%0d",
            txn.address, txn.burst_len+1), UVM_HIGH)

        ap.write(txn);
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf(
            "[MONITOR REPORT] Writes=%0d Reads=%0d ECC_Corrected=%0d ECC_Uncorrectable=%0d",
            write_count, read_count, ecc_corrected_count, ecc_uncorrectable_count), UVM_NONE)
    endfunction

endclass : controller_monitor

`endif

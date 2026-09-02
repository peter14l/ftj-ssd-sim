`ifndef CONTROLLER_DRIVER_SV
`define CONTROLLER_DRIVER_SV

class controller_driver extends uvm_driver #(controller_transaction);
    `uvm_component_utils(controller_driver)

    virtual nvme_flash_if.driver_mp vif;

    function new(string name = "controller_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual nvme_flash_if)::get(this, "", "vif", vif))
            `uvm_fatal("CFG", "controller_driver: virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        controller_transaction txn;
        // Initialize all driven signals to idle
        vif.driver_cb.axi_awvalid <= 0;
        vif.driver_cb.axi_wvalid  <= 0;
        vif.driver_cb.axi_bready  <= 1;
        vif.driver_cb.axi_arvalid <= 0;
        vif.driver_cb.axi_rready  <= 1;
        vif.driver_cb.axi_wlast   <= 0;
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(txn);
            if (txn.cmd_type == 1'b1)
                drive_write(txn);
            else
                drive_read(txn);
            seq_item_port.item_done();
        end
    endtask

    // Drive AXI4 write burst transaction
    task drive_write(controller_transaction txn);
        // --- Write Address Channel ---
        vif.driver_cb.axi_awvalid <= 1;
        vif.driver_cb.axi_awaddr  <= txn.address;
        vif.driver_cb.axi_awlen   <= txn.burst_len;
        vif.driver_cb.axi_awsize  <= 3'b011;   // 8 bytes
        vif.driver_cb.axi_awburst <= 2'b01;    // INCR
        vif.driver_cb.axi_awid    <= 4'h0;
        // Wait for awready handshake
        do @(vif.driver_cb); while (!vif.driver_cb.axi_awready);
        vif.driver_cb.axi_awvalid <= 0;

        // --- Write Data Channel (burst beats) ---
        for (int beat = 0; beat <= txn.burst_len; beat++) begin
            vif.driver_cb.axi_wvalid <= 1;
            vif.driver_cb.axi_wdata  <= txn.payload[beat];
            vif.driver_cb.axi_wstrb  <= txn.wstrb;
            vif.driver_cb.axi_wlast  <= (beat == txn.burst_len) ? 1'b1 : 1'b0;
            do @(vif.driver_cb); while (!vif.driver_cb.axi_wready);
        end
        vif.driver_cb.axi_wvalid <= 0;
        vif.driver_cb.axi_wlast  <= 0;

        // --- Write Response Channel ---
        vif.driver_cb.axi_bready <= 1;
        do @(vif.driver_cb); while (!vif.driver_cb.axi_bvalid);
        if (vif.driver_cb.axi_bresp !== 2'b00)
            `uvm_error("DRV", $sformatf("Write response error: bresp=0x%0h", vif.driver_cb.axi_bresp))
        @(vif.driver_cb);
    endtask

    // Drive AXI4 read burst transaction
    task drive_read(controller_transaction txn);
        // --- Read Address Channel ---
        vif.driver_cb.axi_arvalid <= 1;
        vif.driver_cb.axi_araddr  <= txn.address;
        vif.driver_cb.axi_arlen   <= txn.burst_len;
        vif.driver_cb.axi_arsize  <= 3'b011;
        vif.driver_cb.axi_arburst <= 2'b01;
        vif.driver_cb.axi_arid    <= 4'h0;
        do @(vif.driver_cb); while (!vif.driver_cb.axi_arready);
        vif.driver_cb.axi_arvalid <= 0;

        // --- Read Data Channel ---
        vif.driver_cb.axi_rready  <= 1;
        do @(vif.driver_cb); while (!vif.driver_cb.axi_rvalid);
        // Capture beats until rlast
        do begin
            if (vif.driver_cb.axi_rresp !== 2'b00)
                `uvm_error("DRV", "Read response error")
            @(vif.driver_cb);
        end while (!vif.driver_cb.axi_rlast);
    endtask

endclass : controller_driver

`endif

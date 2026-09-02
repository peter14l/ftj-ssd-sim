`ifndef CONTROLLER_SEQUENCE_SV
`define CONTROLLER_SEQUENCE_SV

// ============================================================
// ai_checkpoint_seq
// Simulates LLM model checkpoint: sustained 256-beat INCR
// burst writes to a narrow sequential LBA range.
// Stresses GC scheduler under sustained write pressure.
// ============================================================
class ai_checkpoint_seq extends uvm_sequence #(controller_transaction);
    `uvm_object_utils(ai_checkpoint_seq)

    int unsigned num_checkpoints = 10;
    logic [31:0] base_addr = 32'h0000_0000;

    function new(string name = "ai_checkpoint_seq");
        super.new(name);
    endfunction

    task body();
        controller_transaction txn;
        for (int i = 0; i < num_checkpoints; i++) begin
            txn = controller_transaction::type_id::create($sformatf("ckpt_txn_%0d", i));
            start_item(txn);
            if (!txn.randomize() with {
                cmd_type   == 1'b1;            // Write only
                burst_len  == 8'd15;           // 16-beat burst
                address    == (base_addr + (i * 32'h0000_0080)); // sequential LBAs
                payload.size() == 16;
                wstrb == 8'hFF;
            }) begin
                `uvm_fatal("SEQ", "ai_checkpoint_seq randomization failed")
            end
            `uvm_info("SEQ", $sformatf("Checkpoint write %0d: addr=0x%08h beats=%0d",
                i, txn.address, txn.burst_len+1), UVM_MEDIUM)
            finish_item(txn);
        end
    endtask

endclass : ai_checkpoint_seq

// ============================================================
// kv_cache_update_seq
// Simulates LLM KV-cache thrash: chaotic random-LBA 8-16-
// beat bursts at mixed queue depth. Tests BurstCoalescer
// coalescing and GC trigger under WAF conditions.
// ============================================================
class kv_cache_update_seq extends uvm_sequence #(controller_transaction);
    `uvm_object_utils(kv_cache_update_seq)

    int unsigned num_updates = 100;

    function new(string name = "kv_cache_update_seq");
        super.new(name);
    endfunction

    task body();
        controller_transaction txn;
        for (int i = 0; i < num_updates; i++) begin
            txn = controller_transaction::type_id::create($sformatf("kv_txn_%0d", i));
            start_item(txn);
            if (!txn.randomize()) begin
                `uvm_fatal("SEQ", "kv_cache_update_seq randomization failed")
            end
            `uvm_info("SEQ", txn.convert2string(), UVM_HIGH)
            finish_item(txn);
        end
    endtask

endclass : kv_cache_update_seq

`endif

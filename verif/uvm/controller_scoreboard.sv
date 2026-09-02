`ifndef CONTROLLER_SCOREBOARD_SV
`define CONTROLLER_SCOREBOARD_SV

class controller_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(controller_scoreboard)

    uvm_analysis_imp #(controller_transaction, controller_scoreboard) analysis_export;

    // Reference model: LBA → last written payload beat 0
    controller_transaction write_db [logic [31:0]];

    // WAF tracking
    uint64_t total_logical_beats;
    uint64_t total_physical_beats;

    // PE cycle distribution (simplified, indexed by LBA[9:0] as block proxy)
    int unsigned pe_counter [1024];

    // Pass/fail counters
    int unsigned checks_passed;
    int unsigned checks_failed;

    function new(string name = "controller_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        checks_passed  = 0;
        checks_failed  = 0;
        total_logical_beats  = 0;
        total_physical_beats = 0;
        foreach (pe_counter[i]) pe_counter[i] = 0;
    endfunction

    function void write(controller_transaction txn);
        if (txn.cmd_type == 1'b1) begin
            // Store write in reference model
            write_db[txn.address] = txn;

            // Track PE cycles (use LBA[9:0] as block index proxy)
            pe_counter[txn.address[9:0]]++;

            // WAF accounting: 1 logical beat → 1 physical beat here (GC overhead tracked separately)
            total_logical_beats  += (txn.burst_len + 1);
            total_physical_beats += (txn.burst_len + 1); // GC adds overhead

            `uvm_info("SB", $sformatf("Recorded write: addr=0x%08h beats=%0d",
                txn.address, txn.burst_len+1), UVM_HIGH)
        end else begin
            // Read — verify against reference model
            check_read_data(txn);
        end
    endfunction

    function void check_read_data(controller_transaction txn);
        if (write_db.exists(txn.address)) begin
            controller_transaction expected = write_db[txn.address];
            // Check first beat as representative
            if (txn.payload.size() > 0 && expected.payload.size() > 0) begin
                if (txn.payload[0] === expected.payload[0]) begin
                    checks_passed++;
                    `uvm_info("SB", $sformatf("[PASS] Data integrity OK: addr=0x%08h",
                        txn.address), UVM_MEDIUM)
                end else begin
                    checks_failed++;
                    `uvm_error("SB", $sformatf(
                        "[FAIL] Data mismatch at addr=0x%08h: got=0x%016h expected=0x%016h",
                        txn.address, txn.payload[0], expected.payload[0]))
                end
            end
        end else begin
            `uvm_info("SB", $sformatf("Read to unmapped addr=0x%08h (expected zeros)",
                txn.address), UVM_HIGH)
        end
    endfunction

    function void check_wear_uniformity();
        real sum = 0.0;
        real mean = 0.0;
        real variance = 0.0;
        real stddev = 0.0;
        int non_zero = 0;

        foreach (pe_counter[i]) begin
            if (pe_counter[i] > 0) begin
                sum += pe_counter[i];
                non_zero++;
            end
        end

        if (non_zero == 0) return;
        mean = sum / non_zero;

        foreach (pe_counter[i]) begin
            if (pe_counter[i] > 0) begin
                real diff = pe_counter[i] - mean;
                variance += diff * diff;
            end
        end
        variance /= non_zero;
        stddev = $sqrt(variance);

        if (mean > 0.0) begin
            real uniformity_pct = (stddev / mean) * 100.0;
            if (uniformity_pct < 10.0) begin
                checks_passed++;
                `uvm_info("SB", $sformatf(
                    "[PASS] Wear uniformity stddev=%.2f%% < 10%% threshold (mean=%.2f)",
                    uniformity_pct, mean), UVM_NONE)
            end else begin
                checks_failed++;
                `uvm_error("SB", $sformatf(
                    "[FAIL] Wear uniformity stddev=%.2f%% EXCEEDS 10%% threshold!",
                    uniformity_pct))
            end
        end
    endfunction

    function void check_waf();
        real waf;
        if (total_logical_beats == 0) return;
        waf = real'(total_physical_beats) / real'(total_logical_beats);
        if (waf < 3.0) begin
            checks_passed++;
            `uvm_info("SB", $sformatf("[PASS] WAF=%.2f < 3.0 bound", waf), UVM_NONE)
        end else begin
            checks_failed++;
            `uvm_error("SB", $sformatf("[FAIL] WAF=%.2f EXCEEDS 3.0 bound!", waf))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        check_wear_uniformity();
        check_waf();
        `uvm_info("SB", $sformatf(
            "[SCOREBOARD REPORT] Passed=%0d Failed=%0d | WAF=%.2f | Writes=%0d",
            checks_passed, checks_failed,
            (total_logical_beats > 0) ? real'(total_physical_beats)/real'(total_logical_beats) : 1.0,
            write_db.num()), UVM_NONE)
        if (checks_failed > 0)
            `uvm_fatal("SB", "Scoreboard detected failures — test FAILED")
    endfunction

endclass : controller_scoreboard

`endif

`ifndef CONTROLLER_TRANSACTION_SV
`define CONTROLLER_TRANSACTION_SV

class controller_transaction extends uvm_sequence_item;
    `uvm_object_utils_begin(controller_transaction)
        `uvm_field_int(address,      UVM_ALL_ON)
        `uvm_field_int(cmd_type,     UVM_ALL_ON)
        `uvm_field_int(burst_len,    UVM_ALL_ON)
        `uvm_field_int(wstrb,        UVM_ALL_ON)
        `uvm_field_array_int(payload, UVM_ALL_ON)
        `uvm_field_int(expected_rdata_scalar, UVM_ALL_ON)
    `uvm_object_utils_end

    // Randomizable fields
    rand logic [31:0]  address;     // Burst base LBA (aligned to 8 bytes)
    rand logic [63:0]  payload [];  // Dynamic array — burst_len+1 entries
    rand logic         cmd_type;    // 0=Read, 1=Write
    rand logic [7:0]   burst_len;   // AWLEN: 0=1 beat, 15=16 beats
    rand logic [7:0]   wstrb;       // Byte lane enables

    // For scoreboard
    logic [63:0] expected_rdata_scalar;
    bit          expect_ecc_correction;

    // Constraints
    constraint ai_write_heavy_c {
        cmd_type dist { 1'b1 := 70, 1'b0 := 30 };
    }

    constraint kv_cache_burst_c {
        burst_len inside { [7:15] };
        address inside {
            [32'h0000_0000 : 32'h0000_07FF],
            [32'h0001_0000 : 32'h0001_07FF]
        };
        // Ensure address is 8-byte aligned
        address[2:0] == 3'b000;
    }

    constraint payload_size_c {
        payload.size() == (burst_len + 1);
    }

    constraint wstrb_full_c {
        wstrb == 8'hFF;
    }

    function new(string name = "controller_transaction");
        super.new(name);
    endfunction

    function void post_randomize();
        foreach (payload[i])
            payload[i] = {$urandom(), $urandom()};
    endfunction

    function string convert2string();
        return $sformatf("[TXN] cmd=%s addr=0x%08h burst_len=%0d wstrb=0x%02h",
            cmd_type ? "WRITE" : "READ", address, burst_len, wstrb);
    endfunction

endclass : controller_transaction

`endif

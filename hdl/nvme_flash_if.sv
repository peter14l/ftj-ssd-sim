`ifndef NVME_FLASH_IF_SV
`define NVME_FLASH_IF_SV
// nvme_flash_if.sv
// AXI4 Full-Burst + NAND Parallel Bus Interface
// For FTJ SSD Controller UVM Testbench
// clk: 100MHz posedge | rst_n: active-low

interface nvme_flash_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 4
)(
    input logic clk,
    input logic rst_n
);
    // Write Address Channel
    logic                       axi_awvalid;
    logic                       axi_awready;
    logic [ADDR_WIDTH-1:0]      axi_awaddr;
    logic [7:0]                 axi_awlen;
    logic [2:0]                 axi_awsize;
    logic [1:0]                 axi_awburst;
    logic [ID_WIDTH-1:0]        axi_awid;

    // Write Data Channel
    logic                       axi_wvalid;
    logic                       axi_wready;
    logic [DATA_WIDTH-1:0]      axi_wdata;
    logic [(DATA_WIDTH/8)-1:0]  axi_wstrb;
    logic                       axi_wlast;

    // Write Response Channel
    logic                       axi_bvalid;
    logic                       axi_bready;
    logic [1:0]                 axi_bresp;
    logic [ID_WIDTH-1:0]        axi_bid;

    // Read Address Channel
    logic                       axi_arvalid;
    logic                       axi_arready;
    logic [ADDR_WIDTH-1:0]      axi_araddr;
    logic [7:0]                 axi_arlen;
    logic [2:0]                 axi_arsize;
    logic [1:0]                 axi_arburst;
    logic [ID_WIDTH-1:0]        axi_arid;

    // Read Data Channel
    logic                       axi_rvalid;
    logic                       axi_rready;
    logic [DATA_WIDTH-1:0]      axi_rdata;
    logic [1:0]                 axi_rresp;
    logic                       axi_rlast;
    logic [ID_WIDTH-1:0]        axi_rid;

    // NAND Flash Parallel Bus
    logic [7:0]  nand_io;
    logic        nand_cle;
    logic        nand_ale;
    logic        nand_re_n;
    logic        nand_we_n;
    logic        nand_ce_n;
    logic        nand_rb_n;

    // ECC Status
    logic host_ecc_corrected;
    logic host_ecc_uncorrectable;

    // Driver clocking block (master perspective)
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output axi_awvalid, axi_awaddr, axi_awlen, axi_awsize, axi_awburst, axi_awid;
        output axi_wvalid, axi_wdata, axi_wstrb, axi_wlast;
        output axi_bready;
        output axi_arvalid, axi_araddr, axi_arlen, axi_arsize, axi_arburst, axi_arid;
        output axi_rready;
        input  axi_awready;
        input  axi_wready;
        input  axi_bvalid, axi_bresp, axi_bid;
        input  axi_arready;
        input  axi_rvalid, axi_rdata, axi_rresp, axi_rlast, axi_rid;
    endclocking

    // Monitor clocking block (passive)
    clocking monitor_cb @(posedge clk);
        default input #1;
        input axi_awvalid, axi_awaddr, axi_awlen, axi_awburst, axi_awready;
        input axi_wvalid, axi_wdata, axi_wstrb, axi_wlast, axi_wready;
        input axi_bvalid, axi_bresp, axi_bready;
        input axi_arvalid, axi_araddr, axi_arlen, axi_arready;
        input axi_rvalid, axi_rdata, axi_rresp, axi_rlast, axi_rready;
        input nand_cle, nand_ale, nand_re_n, nand_we_n, nand_rb_n;
        input host_ecc_corrected, host_ecc_uncorrectable;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk, rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, rst_n);

endinterface : nvme_flash_if
`endif

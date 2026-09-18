`timescale 1ns / 1ps

module tb_USBInterface ();

  wire [ 4:0] okUH;
  wire [ 2:0] okHU;
  wire [31:0] okUHU;
  wire        okAA;

  //------------------------------------------------------------------------
  // okHost Simulation setup. See https://docs.opalkelly.com/fpsdk/frontpanel-hdl/frontpanel-hdl-host-simulation/
  //------------------------------------------------------------------------
  parameter integer BlockDelayStates = 5;
  parameter integer ReadyCheckDelay = 5;
  parameter integer PostReadyDelay = 5;
  parameter integer pipeInSize = 128;
  parameter integer pipeOutSize = 128;
  parameter integer registerSetSize = 32;
  parameter integer Tsys_clk = 5;  // 100Mhz
  // Pipes
  integer k;
  reg [7:0] pipeIn[0:(pipeInSize-1)];
  initial for (k = 0; k < pipeInSize; k = k + 1) pipeIn[k] = 8'h00;
  reg [7:0] pipeOut[0:(pipeOutSize-1)];
  initial for (k = 0; k < pipeOutSize; k = k + 1) pipeOut[k] = 8'h00;
  // Registers
  reg [31:0] u32Address[0:(registerSetSize-1)];
  reg [31:0] u32Data   [0:(registerSetSize-1)];
  reg [31:0] u32Count;
  // Constants
  wire [31:0] NO_MASK = 32'hffffffff;
  //-------------------------------------------------------------------------

  //----DDR3 parameters----
  parameter SIM_BYPASS_INIT_CAL = "FAST";
  parameter COL_WIDTH = 10;  // # of memory Column Address bits.
  parameter CS_WIDTH = 1;  // # of unique CS outputs to memory.
  parameter DM_WIDTH = 4;  // # of DM (data mask)
  parameter DQ_WIDTH = 32;  // # of DQ (data)
  parameter DQS_WIDTH = 4;
  parameter DQS_CNT_WIDTH = 2;  // = ceil(log2(DQS_WIDTH))
  parameter DRAM_WIDTH = 8;  // # of DQ per DQS
  parameter ECC = "OFF";
  parameter RANKS = 1;  // # of Ranks.
  parameter ODT_WIDTH = 1;  // # of ODT outputs to memory.
  parameter ROW_WIDTH = 15;  // # of memory Row Address bits.
  parameter ADDR_WIDTH = 29;
  // # = RANK_WIDTH + BANK_WIDTH
  //     + ROW_WIDTH + COL_WIDTH;
  // Chip Select is always tied to low for
  // single rank devices
  localparam real TPROP_DQS = 0.00;  // Delay for DQS signal during Write Operation
  localparam real TPROP_DQS_RD = 0.00;  // Delay for DQS signal during Read Operation
  localparam real TPROP_PCB_CTRL = 0.00;  // Delay for Address and Ctrl signals
  localparam real TPROP_PCB_DATA = 0.00;  // Delay for data signal during Write operation
  localparam real TPROP_PCB_DATA_RD = 0.00;  // Delay for data signal during Read operation
  //-----

  reg clk_p, clk_n, in_man;
  wire         dec_clk;
  wire         dec_bit;
  wire         ddr3_init_complete;

  // ddr3
  wire         ddr3_reset_n;
  wire [ 31:0] ddr3_dq_fpga;
  wire [ 14:0] ddr3_addr_fpga;
  wire [2 : 0] ddr3_ba_fpga;
  wire [0 : 0] ddr3_ck_p_fpga;
  wire [0 : 0] ddr3_ck_n_fpga;
  wire [0 : 0] ddr3_cke_fpga;
  wire         ddr3_cas_n_fpga;
  wire         ddr3_ras_n_fpga;
  wire         ddr3_we_n_fpga;
  wire [0 : 0] ddr3_odt_fpga;
  wire [3 : 0] ddr3_dm_fpga;
  wire [3 : 0] ddr3_dqs_p_fpga;
  wire [3 : 0] ddr3_dqs_n_fpga;
  wire [ 31:0] ddr3_dq_sdram;
  reg  [ 14:0] ddr3_addr_sdram;
  reg  [2 : 0] ddr3_ba_sdram;
  reg  [0 : 0] ddr3_ck_p_sdram;
  reg  [0 : 0] ddr3_ck_n_sdram;
  reg  [0 : 0] ddr3_cke_sdram;
  reg          ddr3_cas_n_sdram;
  reg          ddr3_ras_n_sdram;
  reg          ddr3_we_n_sdram;
  wire [0 : 0] ddr3_odt_sdram;
  wire [3 : 0] ddr3_dm_sdram;
  wire [3 : 0] ddr3_dqs_p_sdram;
  wire [3 : 0] ddr3_dqs_n_sdram;
  reg  [  3:0] ddr3_dm_sdram_tmp;
  reg  [  0:0] ddr3_odt_sdram_tmp;

  reg          sys_rst_n;
  localparam RESET_PERIOD = 200;
  initial begin
    sys_rst_n = 1'b0;
    #RESET_PERIOD sys_rst_n = 1'b1;
  end


  always @(*) begin
    ddr3_ck_p_sdram <= #(TPROP_PCB_CTRL) ddr3_ck_p_fpga;
    ddr3_ck_n_sdram <= #(TPROP_PCB_CTRL) ddr3_ck_n_fpga;
    ddr3_addr_sdram <= #(TPROP_PCB_CTRL) ddr3_addr_fpga;
    ddr3_ba_sdram <= #(TPROP_PCB_CTRL) ddr3_ba_fpga;
    ddr3_ras_n_sdram <= #(TPROP_PCB_CTRL) ddr3_ras_n_fpga;
    ddr3_cas_n_sdram <= #(TPROP_PCB_CTRL) ddr3_cas_n_fpga;
    ddr3_we_n_sdram <= #(TPROP_PCB_CTRL) ddr3_we_n_fpga;
    ddr3_cke_sdram <= #(TPROP_PCB_CTRL) ddr3_cke_fpga;
  end
  assign ddr3_cs_n_sdram = {(CS_WIDTH * 1) {1'b0}};
  always @(*) ddr3_dm_sdram_tmp <= #(TPROP_PCB_DATA) ddr3_dm_fpga;  //DM signal generation
  assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;
  always @(*) ddr3_odt_sdram_tmp <= #(TPROP_PCB_CTRL) ddr3_odt_fpga;
  assign ddr3_odt_sdram = ddr3_odt_sdram_tmp;
  // Controlling the bi-directional BUS
  genvar dqwd;
  generate
    for (dqwd = 1; dqwd < DQ_WIDTH; dqwd = dqwd + 1) begin : dq_delay
      WireDelay #(
          .Delay_g   (TPROP_PCB_DATA),
          .Delay_rd  (TPROP_PCB_DATA_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dq (
          .A            (ddr3_dq_fpga[dqwd]),
          .B            (ddr3_dq_sdram[dqwd]),
          .reset        (sys_rst_n),
          .phy_init_done(init_calib_complete)
      );
    end
    WireDelay #(
        .Delay_g   (TPROP_PCB_DATA),
        .Delay_rd  (TPROP_PCB_DATA_RD),
        .ERR_INSERT("OFF")
    ) u_delay_dq_0 (
        .A            (ddr3_dq_fpga[0]),
        .B            (ddr3_dq_sdram[0]),
        .reset        (sys_rst_n),
        .phy_init_done(init_calib_complete)
    );
  endgenerate
  genvar dqswd;
  generate
    for (dqswd = 0; dqswd < DQS_WIDTH; dqswd = dqswd + 1) begin : dqs_delay
      WireDelay #(
          .Delay_g   (TPROP_DQS),
          .Delay_rd  (TPROP_DQS_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dqs_p (
          .A            (ddr3_dqs_p_fpga[dqswd]),
          .B            (ddr3_dqs_p_sdram[dqswd]),
          .reset        (sys_rst_n),
          .phy_init_done(init_calib_complete)
      );

      WireDelay #(
          .Delay_g   (TPROP_DQS),
          .Delay_rd  (TPROP_DQS_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dqs_n (
          .A            (ddr3_dqs_n_fpga[dqswd]),
          .B            (ddr3_dqs_n_sdram[dqswd]),
          .reset        (sys_rst_n),
          .phy_init_done(init_calib_complete)
      );
    end
  endgenerate


  USBInterface dut (
      .sysClkp(clk_p),
      .sysClkn(clk_n),
      .okUH(okUH),
      .okHU(okHU),
      .okUHU(okUHU),
      .okAA(okAA),
      .manchester(in_man),
      .manchester2(in_man),
      .dbg_sig0(),
      .dbg_sig2(ddr3_init_complete),
      .dbg_sig3(dec_bit),
      .ddr3_dq(ddr3_dq_fpga),
      .ddr3_addr(ddr3_addr_fpga),
      .ddr3_ba(ddr3_ba_fpga),
      .ddr3_ck_p(ddr3_ck_p_fpga),
      .ddr3_ck_n(ddr3_ck_n_fpga),
      .ddr3_cke(ddr3_cke_fpga),
      .ddr3_cas_n(ddr3_cas_n_fpga),
      .ddr3_ras_n(ddr3_ras_n_fpga),
      .ddr3_we_n(ddr3_we_n_fpga),
      .ddr3_odt(ddr3_odt_fpga),
      .ddr3_dm(ddr3_dm_fpga),
      .ddr3_dqs_p(ddr3_dqs_p_fpga),
      .ddr3_dqs_n(ddr3_dqs_n_fpga),
      .ddr3_reset_n(ddr3_reset_n)
  );

  // see https://support.xilinx.com/s/question/0D52E00006hph1mSAA/ddr-3-simulation-mig?language=en_US
  genvar i;
  generate
    for (i = 0; i < 2; i = i + 1) begin : gen_mem
      ddr3_model u_comp_ddr3 (
          .rst_n  (ddr3_reset_n),
          .ck     (ddr3_ck_p_sdram),
          .ck_n   (ddr3_ck_n_sdram),
          .cke    (ddr3_cke_sdram),
          .cs_n   (1'b0),
          .ras_n  (ddr3_ras_n_sdram),
          .cas_n  (ddr3_cas_n_sdram),
          .we_n   (ddr3_we_n_sdram),
          .dm_tdqs(ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
          .ba     (ddr3_ba_sdram),
          .addr   (ddr3_addr_sdram),
          .dq     (ddr3_dq_sdram[16*(i+1)-1:16*(i)]),
          .dqs    (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
          .dqs_n  (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
          .tdqs_n (),
          .odt    (ddr3_odt_sdram)
      );
    end
  endgenerate

  integer fd_input;
  integer fd_output;
  integer dt;
  integer irst;
  reg val;
  reg input_stream = 1'b0;

  initial begin : data_input
    clk_p  = 1'b0;
    clk_n  = 1'b1;
    in_man = 1'b0;
    FrontPanelReset;
    #100 SetWireInValue(8'h00, 32'h00000002, NO_MASK);
    UpdateWireIns;
    for (irst = 0; irst < 3; irst = irst + 1) begin
      #10 in_man = 1'b1;
      #10 in_man = 1'b0;
    end
    #100 SetWireInValue(8'h00, 32'h00000008, NO_MASK);
    UpdateWireIns;
    #2000 SetWireInValue(8'h00, 32'h00000000, NO_MASK);
    UpdateWireIns;
    wait (ddr3_init_complete);
    fd_input =
        $fopen("/home/bendog/Documents/git/wireless_fpga_daq/hdl/source/sim/stimulus.csv", "r");
    $display("input start at %t", $realtime);
    input_stream = 1'b1;
    while (!$feof(
        fd_input
    )) begin
      $fscanf(fd_input, "%d,%b", dt, val);
      #(dt) in_man <= val;
    end
    $display("input finished");
    $fclose(fd_input);
    input_stream = 1'b0;
    while (1'b1) begin
      #50 in_man <= ~in_man;  // keeps input running to push out all data
    end
  end

  integer i_byte;
  integer j_bit;

  initial begin : data_output
    fd_output =
        $fopen("/home/bendog/Documents/git/wireless_fpga_daq/hdl/source/sim/output.csv", "w");
    $display("finish opening");
    wait (input_stream);
    $display("start reading");
    while (input_stream) begin
      $display("reading");
      ReadFromBlockPipeOut(8'ha0, 16, 16 * 8);
      // blocksize and length are in bytes
      // call blocks until desired length is read
      $display("read finish");
      for (i_byte = 0; i_byte < pipeOutSize; i_byte = i_byte + 1) begin
        for (j_bit = 0; j_bit < 8; j_bit = j_bit + 1) begin
          $fwrite(fd_output, "%d", pipeOut[i_byte][j_bit]);
        end
      end
    end
    $display("done reading");
    $fclose(fd_output);
    $finish();
  end

  always #(2.5) clk_p <= ~clk_p;
  always #(2.5) clk_n <= ~clk_n;

  `include "./okSim/okHostCalls.vh"

endmodule

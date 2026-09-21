`timescale 1ns / 1ps

// Behavioural stand-in for xem7310_a75_mig, for simulation only.
//
// Why this exists
// ---------------
// MIG calibration does not converge against the Micron DDR3 model in this
// project: the model reports tWLS violations on DQS and init_calib_complete
// never asserts, within any simulated time anyone has been willing to wait
// (2 ms was not enough). The consequence is that **nothing behind the memory
// controller has ever been simulated here** -- not channel 1, and, since
// channel 2 moved onto DDR3, not channel 2 either.
//
// This replaces the controller, not the design. Swapping it in keeps the
// arbiter, both input FIFOs, both output FIFOs, the reset sequencer and both
// Opal Kelly pipes exactly as built; only the external memory controller and
// the DRAM behind it become a model. That is a very different thing from
// giving the simulation a shortcut datapath, which would test something the
// bitfile does not contain.
//
// What it is faithful about
// -------------------------
// The parts ddr3_ui can get wrong:
//
//   * Commands are accepted only on (app_en & app_rdy), write data only on
//     (app_wdf_wren & app_wdf_rdy), and both are stalled pseudo-randomly, so
//     the retry paths in s_write_4 and s_read_1 are exercised rather than
//     skipped.
//   * Write data and write commands are queued independently and paired in
//     order, so a design that supplies them in either order works here exactly
//     as it would on hardware. ddr3_ui happens to supply them coincidentally.
//   * Read data comes back RD_LATENCY cycles later through app_rd_data_valid,
//     not combinationally.
//   * init_calib_complete is low for a while after reset, so the calib_done
//     gate is real.
//
// What it is NOT
// --------------
// Not a DDR3 model. No refresh, no bank/row timing, no bandwidth limit, no
// reordering between reads and writes. It cannot tell you the design meets
// DDR3 timing or that the MIG is configured correctly -- only that the logic
// driving the user interface is correct. Timing closure and the real
// controller remain a hardware question.

module mig_ui_model #(
    // Cycles after reset release before calibration reports done.
    parameter int CALIB_CYCLES = 200,
    // Cycles between a read command being accepted and its data appearing.
    parameter int RD_LATENCY = 8,
    // 0 disables stalling (app_rdy and app_wdf_rdy always high). Non-zero is
    // roughly the percentage of cycles in which each is withheld.
    parameter int STALL_PCT = 12
) (
    // Memory interface. Driven to constants: with this module in place the
    // Micron model is not instantiated, so nothing reads them.
    output wire [14:0] ddr3_addr,
    output wire [ 2:0] ddr3_ba,
    output wire        ddr3_cas_n,
    output wire [ 0:0] ddr3_ck_n,
    output wire [ 0:0] ddr3_ck_p,
    output wire [ 0:0] ddr3_cke,
    output wire        ddr3_ras_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_we_n,
    inout  wire [31:0] ddr3_dq,
    inout  wire [ 3:0] ddr3_dqs_n,
    inout  wire [ 3:0] ddr3_dqs_p,
    output wire [ 3:0] ddr3_dm,
    output wire [ 0:0] ddr3_odt,
    output reg         init_calib_complete,

    // Application interface
    input  wire [ 28:0] app_addr,
    input  wire [  2:0] app_cmd,
    input  wire         app_en,
    input  wire [255:0] app_wdf_data,
    input  wire         app_wdf_end,
    input  wire         app_wdf_wren,
    input  wire [ 31:0] app_wdf_mask,
    output reg  [255:0] app_rd_data,
    output reg          app_rd_data_end,
    output reg          app_rd_data_valid,
    output wire         app_rdy,
    output wire         app_wdf_rdy,
    input  wire         app_sr_req,
    input  wire         app_ref_req,
    input  wire         app_zq_req,
    output wire         app_sr_active,
    output wire         app_ref_ack,
    output wire         app_zq_ack,

    output reg ui_clk,
    output reg ui_clk_sync_rst,

    input wire sys_clk_i,
    input wire sys_rst    // ACTIVE HIGH, per mig.prj <SysResetPolarity>
);

  localparam CMD_WRITE = 3'b000;
  localparam CMD_READ = 3'b001;

  // The memory interface goes nowhere. Hold the DRAM in reset and keep the
  // clock quiet so that if anyone does reattach the Micron model, it stays
  // silent rather than reporting violations against a dead interface.
  assign ddr3_addr     = 15'b0;
  assign ddr3_ba       = 3'b0;
  assign ddr3_cas_n    = 1'b1;
  assign ddr3_ras_n    = 1'b1;
  assign ddr3_we_n     = 1'b1;
  assign ddr3_ck_p     = 1'b0;
  assign ddr3_ck_n     = 1'b1;
  assign ddr3_cke      = 1'b0;
  assign ddr3_reset_n  = 1'b0;
  assign ddr3_dm       = 4'b0;
  assign ddr3_odt      = 1'b0;
  assign ddr3_dq       = 32'bz;
  assign ddr3_dqs_p    = 4'bz;
  assign ddr3_dqs_n    = 4'bz;

  assign app_sr_active = 1'b0;
  assign app_ref_ack   = 1'b0;
  assign app_zq_ack    = 1'b0;

  //=============== Clocking ===============
  //
  // PHYRatio is 4:1 and the input clock is 200 MHz, so ui_clk is 100 MHz --
  // sys_clk_i divided by two. The 256-bit user interface is consistent with
  // that: 4 x 2 x 32 bit.
  initial ui_clk = 1'b0;
  always @(posedge sys_clk_i) ui_clk <= ~ui_clk;

  // ui_clk_sync_rst is active high and is released synchronously a few cycles
  // after sys_rst goes away, as the real controller does.
  integer rst_cnt = 0;
  initial begin
    ui_clk_sync_rst = 1'b1;
    init_calib_complete = 1'b0;
  end

  integer calib_cnt = 0;
  always @(posedge ui_clk) begin
    if (sys_rst) begin
      ui_clk_sync_rst     <= 1'b1;
      init_calib_complete <= 1'b0;
      rst_cnt             <= 0;
      calib_cnt           <= 0;
    end else begin
      if (rst_cnt < 8) begin
        rst_cnt <= rst_cnt + 1;
      end else begin
        ui_clk_sync_rst <= 1'b0;
        // Calibration takes a while, and the design has to wait for it.
        if (calib_cnt < CALIB_CYCLES) calib_cnt <= calib_cnt + 1;
        else init_calib_complete <= 1'b1;
      end
    end
  end

  //=============== Ready generation ===============
  //
  // Withholding these is the whole point: a design that only works when the
  // controller is always ready is a design that does not work.
  reg [31:0] lfsr = 32'h1234_5678;
  always @(posedge ui_clk) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

  wire stall_cmd = (STALL_PCT != 0) && ((lfsr[7:0] % 100) < STALL_PCT);
  wire stall_wdf = (STALL_PCT != 0) && ((lfsr[19:12] % 100) < STALL_PCT);

  assign app_rdy = init_calib_complete & ~ui_clk_sync_rst & ~stall_cmd;
  assign app_wdf_rdy = init_calib_complete & ~ui_clk_sync_rst & ~stall_wdf;

  //=============== Memory ===============
  //
  // Sparse: the rings are 256 MiB each and a simulation touches a few dozen
  // addresses, so an associative array costs nothing and needs no bound.
  logic [255:0] mem      [int unsigned];

  // Write commands and write data arrive on independent handshakes and are
  // paired in order, which is what the MIG does. ddr3_ui presents them in the
  // same cycle, but nothing here depends on that.
  int unsigned  waddr_q  [$];
  logic [255:0] wdata_q  [$];

  // Reads in flight, each with its remaining latency.
  int unsigned  raddr_q  [$];
  int           rdelay_q [$];

  int unsigned  a;
  int           i;
  logic [255:0] d;

  always @(posedge ui_clk) begin
    if (ui_clk_sync_rst) begin
      waddr_q.delete();
      wdata_q.delete();
      raddr_q.delete();
      rdelay_q.delete();
      app_rd_data_valid <= 1'b0;
      app_rd_data_end   <= 1'b0;
      app_rd_data       <= '0;
    end else begin
      app_rd_data_valid <= 1'b0;
      app_rd_data_end   <= 1'b0;

      // Accept a write command.
      if (app_en && app_rdy && app_cmd == CMD_WRITE) waddr_q.push_back(app_addr);

      // Accept a read command.
      if (app_en && app_rdy && app_cmd == CMD_READ) begin
        raddr_q.push_back(app_addr);
        rdelay_q.push_back(RD_LATENCY);
      end

      // Accept write data.
      if (app_wdf_wren && app_wdf_rdy) begin
        wdata_q.push_back(app_wdf_data);
        // The design ties the mask to zero. If that ever changes, this model
        // would silently write bytes that hardware would have masked off.
        if (app_wdf_mask !== 32'h0)
          $display("mig_ui_model: WARNING app_wdf_mask=%h is ignored by this model",
                   app_wdf_mask);
      end

      // Retire a write once both halves are present.
      if (waddr_q.size() > 0 && wdata_q.size() > 0) begin
        a = waddr_q.pop_front();
        d = wdata_q.pop_front();
        mem[a] = d;
      end

      // Age reads in flight and return the one that is due.
      for (i = 0; i < rdelay_q.size(); i++) rdelay_q[i] = rdelay_q[i] - 1;
      if (rdelay_q.size() > 0 && rdelay_q[0] <= 0) begin
        a = raddr_q.pop_front();
        void'(rdelay_q.pop_front());
        if (!mem.exists(a)) begin
          // ddr3_ui only reads when its ring is non-empty, so this means the
          // read and write pointers have come apart. Say so loudly rather
          // than returning plausible zeros.
          $display("mig_ui_model: ERROR read of never-written address %0h at %0t", a, $time);
          app_rd_data <= {8{32'hDEADBEEF}};
        end else begin
          app_rd_data <= mem[a];
        end
        app_rd_data_valid <= 1'b1;
        app_rd_data_end   <= 1'b1;
      end
    end
  end

endmodule

// PipeTest.v
//
// This is simple HDL that implements barebones PipeIn and PipeOut
// functionality.  The logic generates and compares againt a pseudorandom
// sequence of data as a way to verify transfer integrity and benchmark the pipe
// transfer speeds.
// ref:
// - https://docs.opalkelly.com/fpsdk/frontpanel-hdl/
// - https://docs.opalkelly.com/fpsdk/system-design/
// - https://docs.opalkelly.com/fpsdk/frontpanel-hdl/frontpanel-hdl-usb-3-0/
// - https://docs.opalkelly.com/xem7310/usb-3-0-host-interface/
//
// Copyright (c) 2005-2011  Opal Kelly Incorporated
// $Rev$ $Date$
//------------------------------------------------------------------------
`include "mandec/mandec.v"
`include "ddr3/ddr3_ui.v"

module USBInterface (
    // clock
    input  wire         sysClkp,
    input  wire         sysClkn,
    // ok interface
    input  wire [  4:0] okUH,
    output wire [  2:0] okHU,
    inout  wire [ 31:0] okUHU,
    inout  wire         okAA,
    // output wire [  7:0] led,
    // decoder and debug
    input  wire         manchester,   // channel 1 input (J2-2)
    input  wire         manchester2,  // channel 2 input (J2-4, formerly dbg_sig1)
    output wire         dbg_sig0,
    output wire         dbg_sig2,
    output wire         dbg_sig3,
    // ddr3
    inout  wire [ 31:0] ddr3_dq,
    output wire [ 14:0] ddr3_addr,
    output wire [2 : 0] ddr3_ba,
    output wire [0 : 0] ddr3_ck_p,
    output wire [0 : 0] ddr3_ck_n,
    output wire [0 : 0] ddr3_cke,
    output wire         ddr3_cas_n,
    output wire         ddr3_ras_n,
    output wire         ddr3_we_n,
    output wire [0 : 0] ddr3_odt,
    output wire [3 : 0] ddr3_dm,
    inout  wire [3 : 0] ddr3_dqs_p,
    inout  wire [3 : 0] ddr3_dqs_n,
    output wire         ddr3_reset_n
);
  //=============== Declaration ===============

  // Clock
  wire          sysClk;
  wire          clk_reset;

  // OK interface bus:
  wire          okClk;
  wire [ 112:0] okHE;
  wire [  64:0] okEH;
  wire [2*65-1:0] okEHx;

  // OK incoming control
  wire [  31:0] ep00wire;

  // OK pipe out (channel 1, 0xA0)
  wire          pipe_ready;
  wire [  31:0] pipe_datain;
  // OK pipe out (channel 2, 0xA1)
  (* mark_debug = "true" *) wire pipe2_ready;
  wire [  31:0] pipe2_datain;

  // Decoder
  wire          data_dly;
  wire          rec_clk;
  wire          genClk;
  wire          dec_data_bit;
  wire [   1:0] dec_data;
  (* mark_debug = "true" *) wire dec_clk;
  // Decoder, channel 2.
  // The (* mark_debug *) nets through the rest of this file are the channel-2
  // chain, kept from being optimised away so an ILA can be attached later
  // without another RTL edit: open the synthesized design and the Set Up Debug
  // wizard picks up every marked net. They are deliberately all scalars so each
  // becomes one probe with no bus reassembly. Nothing reads them today, so they
  // cost only the LUT for dec2_symbol_invalid.
  (* mark_debug = "true" *) wire dec2_data_bit;
  wire [   1:0] dec2_data;
  (* mark_debug = "true" *) wire dec2_clk;
  // Asserted when the decoder sees a non-Manchester symbol (both half-bits
  // equal). This is the condition that makes mandec stall its recovered clock,
  // so it is the single most useful signal for telling "no lock" apart from
  // "locked but no data".
  (* mark_debug = "true" *) wire dec2_symbol_invalid;

  // FIFO
  wire          fifo_chain0_full;
  wire          fifo_chain0_empty;
  wire          fifo_chain0_wr_en;
  wire [   3:0] fifo_chain0_dout;
  wire          fifo_chain1_full;
  wire          fifo_chain1_empty;
  wire          fifo_chain1_wr_en;
  wire [  31:0] fifo_chain1_dout;
  wire          fifo_ddr3_in_full;
  wire          fifo_ddr3_in_empty;
  wire          fifo_ddr3_in_wr_en;
  wire          fifo_ddr3_in_rd_en;
  wire          fifo_ddr3_in_ready;  // ready for ddr3 read
  wire [   6:0] fifo_ddr3_in_rd_data_count;
  wire [ 255:0] fifo_ddr3_in_dout;
  wire          fifo_ddr3_out_full;
  wire          fifo_ddr3_out_empty;
  wire          fifo_ddr3_out_wr_en;
  wire          fifo_ddr3_out_rd_en;
  wire          fifo_ddr3_out_ready;  // ready for ddr3 write
  wire [   6:0] fifo_ddr3_out_wr_data_count;
  wire [ 255:0] fifo_ddr3_out_din;
  wire [  31:0] fifo_ddr3_out_dout;
  // FIFO, channel 2 (BRAM only, no DDR3)
  (* mark_debug = "true" *) wire fifo2_chain0_full;
  (* mark_debug = "true" *) wire fifo2_chain0_empty;
  wire          fifo2_chain0_wr_en;
  wire [   3:0] fifo2_chain0_dout;
  (* mark_debug = "true" *) wire fifo2_chain1_full;
  (* mark_debug = "true" *) wire fifo2_chain1_empty;
  wire          fifo2_chain1_wr_en;
  wire [  31:0] fifo2_chain1_dout;
  (* mark_debug = "true" *) wire fifo2_out_full;
  (* mark_debug = "true" *) wire fifo2_out_empty;
  (* mark_debug = "true" *) wire fifo2_out_wr_en;
  (* mark_debug = "true" *) wire fifo2_out_rd_en;
  wire [  31:0] fifo2_out_dout;

  // ddr3
  reg           sys_rst;
  wire          init_calib_complete;
  wire [28 : 0] app_addr;
  wire [ 2 : 0] app_cmd;
  wire          app_en;
  wire          app_rdy;
  wire [ 255:0] app_rd_data;
  wire          app_rd_data_end;
  wire          app_rd_data_valid;
  wire [ 255:0] app_wdf_data;
  wire          app_wdf_end;
  wire [31 : 0] app_wdf_mask;
  wire          app_wdf_rdy;
  wire          app_wdf_wren;
  wire          ui_clk;
  wire          ui_clk_sync_rst;
  wire          ui_full;
  wire          ui_empty;

  //=============== Instantiation ===============

  // Control signals. These were implicit nets; declared explicitly so the reset
  // ordering can be probed. That ordering is the one thing the testbench does
  // differently from the host: it pulses both channels while fifo_reset is
  // asserted, so dec2_clk is running when fifo2_out resets, and hardware has no
  // such guarantee. fifo2_out is the only pipe-out FIFO whose write clock is a
  // recovered clock rather than a free-running one.
  (* mark_debug = "true" *) wire fifo_reset;
  (* mark_debug = "true" *) wire dec_reset;
  wire ddr3_reset;
  assign clk_reset  = ep00wire[0];
  assign fifo_reset = ep00wire[1];
  assign dec_reset  = ~ep00wire[2];
  assign ddr3_reset = ep00wire[3];

  // LEDs
  //   assign led[0] = fifo_ddr3_in_full ? 1'b0 : 1'bz;
  //   assign led[1] = fifo_ddr3_in_empty ? 1'b0 : 1'bz;
  //   assign led[2] = fifo_ddr3_out_full ? 1'b0 : 1'bz;
  //   assign led[3] = fifo_ddr3_out_empty ? 1'b0 : 1'bz;
  //   assign led[4] = ui_full ? 1'b0 : 1'bz;
  //   assign led[5] = ui_empty ? 1'b0 : 1'bz;

  // Debug outputs. There are only three pins, so they go to whichever question
  // is actually being asked. Right now that is two: how fast can channel 1 run,
  // and why does channel 2 return nothing.
  //
  // DEBUG_BOTH = 1 (default) gives one recovered clock per channel plus channel
  // 2's pipe-ready:
  //
  //   J3-10 (dbg_sig0) = dec_clk      channel 1 recovered clock. Ticking means
  //                                   the decoder locked. This is THE signal to
  //                                   watch when trying an unfamiliar data rate:
  //                                   a dead pin means the decoder never locked,
  //                                   which tells you far more than an empty
  //                                   capture on the host does.
  //   J2-18 (dbg_sig2) = dec2_clk     the same for channel 2.
  //   J2-26 (dbg_sig3) = pipe2_ready  ep_ready for pipe 0xa1. Low forever while
  //                                   dec2_clk is healthy means the fault is the
  //                                   channel-2 FIFO or its reset, not the
  //                                   decoder.
  //
  // This costs dec2_data_bit, which distinguished "channel 2 locked but the data
  // is rubbish" from "locked and fine". It is still driven and marked mark_debug,
  // so an ILA can reach it; it just no longer has a pin.
  //
  // DEBUG_BOTH = 0 restores the three channel-1-era signals this design shipped
  // with (data_dly, init_calib_complete, dec_data_bit) -- note none of those was
  // the recovered clock either.
  //
  // dbg_sig1 does not exist on the two-channel build: that pin (AA6) is
  // manchester2, the channel-2 input.
  // DEBUG_MODE 2 puts the whole channel-1 chain on the pins instead -- clock,
  // then data, then pipe -- which is what you want when testing how fast
  // channel 1 can run, because it says WHICH stage failed rather than just that
  // the capture was empty. Built into hdl/build/ch1_debug/ (not committed).
  //
  //   0 = original   data_dly / init_calib_complete / dec_data_bit
  //   1 = both       dec_clk / dec2_clk / pipe2_ready          <- committed default
  //   2 = channel 1  dec_clk / dec_data_bit / pipe_ready
  localparam [1:0] DEBUG_MODE = 2'd1;
  assign dbg_sig0 = (DEBUG_MODE == 2'd0) ? data_dly : dec_clk;
  assign dbg_sig2 = (DEBUG_MODE == 2'd0) ? init_calib_complete :
                    (DEBUG_MODE == 2'd1) ? dec2_clk : dec_data_bit;
  assign dbg_sig3 = (DEBUG_MODE == 2'd0) ? dec_data_bit :
                    (DEBUG_MODE == 2'd1) ? pipe2_ready : pipe_ready;


  // Clock generatrion
  IBUFGDS osc_clk (
      .O (sysClk),
      .I (sysClkp),
      .IB(sysClkn)
  );
  clk_wiz_0 clk_mult0 (
      .clk_out1(genClk),  // output clk_out1
      .reset   (clk_reset),     // input reset
      .clk_in1 (sysClk)    // input clk_in1
  );

  // Manchester convention, shared by both channels.
  //   1 = IEEE 802.3 (01 -> 1, 10 -> 0)   <- matches the *-IEEE.bit files in miniscope-io
  //   0 = "normal"   (10 -> 1, 01 -> 0)
  localparam MANCHESTER_IEEE = 1'b1;
  function automatic man2bit(input [1:0] pair);
    man2bit = (pair[1] ^ pair[0]) ? (MANCHESTER_IEEE ? pair[0] : pair[1]) : 1'bx;
  endfunction

  // Manchester Decoder, channel 1 (J2-2). Data rate = 100 MHz / Depth(c_shift_ram_0).
  mandec #(10) dec (
      .i_clk(genClk),
      .i_data(manchester),
      .i_reset(dec_reset),
      .o_clk(dec_clk),
      .o_data(dec_data),
      .dbg_man_dly(data_dly),
      .dbg_rec_clk(rec_clk)
  );
  assign dec_data_bit = man2bit(dec_data);

  // Manchester Decoder, channel 2 (J2-4). Same rate/convention; shares c_shift_ram_0.
  mandec #(10) dec2 (
      .i_clk(genClk),
      .i_data(manchester2),
      .i_reset(dec_reset),
      .o_clk(dec2_clk),
      .o_data(dec2_data),
      .dbg_man_dly(),
      .dbg_rec_clk()
  );
  assign dec2_data_bit = man2bit(dec2_data);
  assign dec2_symbol_invalid = (dec2_data == 2'b00) || (dec2_data == 2'b11);

  //=============== FIFO reset sequencing ===============
  //
  // Every FIFO ahead of DDR3 is clocked by a recovered clock, and mandec stalls
  // that clock whenever it is not seeing valid Manchester symbols. A
  // fifo_generator core with an asynchronous reset and the safety circuit
  // enabled needs its clocks running to complete a reset, so pulsing fifo_reset
  // while a channel is idle leaves that channel's FIFOs never accepting writes:
  // prog_empty stays asserted, ep_ready never rises, and ReadFromBlockPipeOut
  // blocks forever. It does not recover when data arrives later.
  //
  // BOTH channels are exposed to this. Channel 1 only escapes it in practice
  // because its transmitter is always already streaming when the host resets.
  // Note this is also why moving channel 2 onto DDR3 would not help: the
  // vulnerable FIFO is fifo_ddr3_in, which is written on dec_clk just the same.
  //
  // So do not hand the host's reset straight to those FIFOs. Hold each channel's
  // reset until its own recovered clock has actually been seen ticking, then
  // release. The FIFO is then always reset with its write clock running, and the
  // reset is held across many of its cycles, which is what fifo_generator asks
  // for. See doc/channel2_debug.md.

  // A free-running toggle in each recovered clock domain, sampled into okClk.
  // Toggle-and-synchronise rather than sampling the clock directly: the clock is
  // far slower than okClk, so no edge is missed, and nothing here depends on the
  // recovered clock being periodic.
  reg dec_toggle = 1'b0;
  reg dec2_toggle = 1'b0;
  always @(posedge dec_clk) dec_toggle <= ~dec_toggle;
  always @(posedge dec2_clk) dec2_toggle <= ~dec2_toggle;

  (* ASYNC_REG = "TRUE" *) reg [2:0] dec_tog_sync = 3'b000;
  (* ASYNC_REG = "TRUE" *) reg [2:0] dec2_tog_sync = 3'b000;
  always @(posedge okClk) dec_tog_sync <= {dec_tog_sync[1:0], dec_toggle};
  always @(posedge okClk) dec2_tog_sync <= {dec2_tog_sync[1:0], dec2_toggle};
  wire dec_tick = dec_tog_sync[2] ^ dec_tog_sync[1];
  wire dec2_tick = dec2_tog_sync[2] ^ dec2_tog_sync[1];

  // Recovered-clock edges to observe before letting a channel out of reset.
  localparam [3:0] RST_TICKS = 4'd8;

  reg [3:0] dec_rst_cnt = 4'd0;
  reg [3:0] dec2_rst_cnt = 4'd0;
  // Held at power-up: a channel stays in reset until its transmitter appears.
  (* mark_debug = "true" *) reg dec_fifo_reset = 1'b1;
  (* mark_debug = "true" *) reg dec2_fifo_reset = 1'b1;

  always @(posedge okClk) begin
    if (fifo_reset) begin
      dec_rst_cnt    <= 4'd0;
      dec_fifo_reset <= 1'b1;
    end else if (dec_fifo_reset & dec_tick) begin
      if (dec_rst_cnt == RST_TICKS) dec_fifo_reset <= 1'b0;
      else dec_rst_cnt <= dec_rst_cnt + 4'd1;
    end
  end

  always @(posedge okClk) begin
    if (fifo_reset) begin
      dec2_rst_cnt    <= 4'd0;
      dec2_fifo_reset <= 1'b1;
    end else if (dec2_fifo_reset & dec2_tick) begin
      if (dec2_rst_cnt == RST_TICKS) dec2_fifo_reset <= 1'b0;
      else dec2_rst_cnt <= dec2_rst_cnt + 4'd1;
    end
  end

  // FIFO
  assign fifo_chain0_wr_en = ~fifo_chain0_full;
  assign fifo_chain1_wr_en = (~fifo_chain0_empty) & (~fifo_chain1_full);
  fifo_w1_1024_r4_256 fifo_chain0 (
      .clk         (dec_clk),            // input wire clk
      .rst         (dec_fifo_reset),     // input wire rst (sequenced, see above)
      .din         (dec_data_bit),       // input wire [0 : 0] din
      .wr_en       (fifo_chain0_wr_en),  // input wire wr_en
      .rd_en       (fifo_chain1_wr_en),  // input wire rd_en
      .dout        (fifo_chain0_dout),   // output wire [3 : 0] dout
      .full        (),                   // output wire full
      .almost_full (fifo_chain0_full),   // output wire almost_full
      .empty       (),                   // output wire empty
      .almost_empty(fifo_chain0_empty),  // output wire almost_empty
      .wr_rst_busy (),                   // output wire wr_rst_busy
      .rd_rst_busy ()                    // output wire rd_rst_busy
  );
  fifo_w4_1024_r32_128 fifo_chain1 (
      .clk         (dec_clk),             // input wire clk
      .rst         (dec_fifo_reset),      // input wire rst (sequenced, see above)
      .din         (fifo_chain0_dout),    // input wire [3 : 0] din
      .wr_en       (fifo_chain1_wr_en),   // input wire wr_en
      .rd_en       (fifo_ddr3_in_wr_en),  // input wire rd_en
      .dout        (fifo_chain1_dout),    // output wire [31 : 0] dout
      .full        (),                    // output wire full
      .almost_full (fifo_chain1_full),    // output wire almost_full
      .empty       (),                    // output wire empty
      .almost_empty(fifo_chain1_empty),   // output wire almost_empty
      .wr_rst_busy (),                    // output wire wr_rst_busy
      .rd_rst_busy ()                     // output wire rd_rst_busy
  );

  // FIFO, channel 2: 1 bit -> 4 bit -> 32 bit, then a 32k-word BRAM buffer to okClk
  assign fifo2_chain0_wr_en = ~fifo2_chain0_full;
  assign fifo2_chain1_wr_en = (~fifo2_chain0_empty) & (~fifo2_chain1_full);
  assign fifo2_out_wr_en    = (~fifo2_chain1_empty) & (~fifo2_out_full);
  fifo_w1_1024_r4_256 fifo2_chain0 (
      .clk         (dec2_clk),
      .rst         (dec2_fifo_reset),
      .din         (dec2_data_bit),
      .wr_en       (fifo2_chain0_wr_en),
      .rd_en       (fifo2_chain1_wr_en),
      .dout        (fifo2_chain0_dout),
      .full        (),
      .almost_full (fifo2_chain0_full),
      .empty       (),
      .almost_empty(fifo2_chain0_empty),
      .wr_rst_busy (),
      .rd_rst_busy ()
  );
  fifo_w4_1024_r32_128 fifo2_chain1 (
      .clk         (dec2_clk),
      .rst         (dec2_fifo_reset),
      .din         (fifo2_chain0_dout),
      .wr_en       (fifo2_chain1_wr_en),
      .rd_en       (fifo2_out_wr_en),
      .dout        (fifo2_chain1_dout),
      .full        (),
      .almost_full (fifo2_chain1_full),
      .empty       (),
      .almost_empty(fifo2_chain1_empty),
      .wr_rst_busy (),
      .rd_rst_busy ()
  );
  // Created by hdl/build/add_ch2_fifo.tcl (fifo_generator 13.2, independent clocks, 32x32768)
  fifo_w32_32768_r32_32768 fifo2_out (
      .rst        (dec2_fifo_reset),
      .wr_clk     (dec2_clk),
      .rd_clk     (okClk),
      .din        (fifo2_chain1_dout),
      .wr_en      (fifo2_out_wr_en),
      .rd_en      (fifo2_out_rd_en),
      .dout       (fifo2_out_dout),
      .full       (),
      .empty      (),
      .prog_full  (fifo2_out_full),
      .prog_empty (fifo2_out_empty),
      .wr_rst_busy(),
      .rd_rst_busy()
  );

  // ddr3
  assign fifo_ddr3_in_wr_en  = (~fifo_chain1_empty) & (~fifo_ddr3_in_full);
  assign fifo_ddr3_in_ready  = (~fifo_ddr3_in_empty) & (~ui_full);
  assign fifo_ddr3_out_ready = (~fifo_ddr3_out_full) & (~ui_empty);
  fifo_w32_1024_r256_128 fifo_ddr3_in (
      .rst          (dec_fifo_reset),                  // input wire rst
      .wr_clk       (dec_clk),                     // input wire wr_clk
      .rd_clk       (ui_clk),                      // input wire rd_clk
      .din          (fifo_chain1_dout),            // input wire [31 : 0] din
      .wr_en        (fifo_ddr3_in_wr_en),          // input wire wr_en
      .rd_en        (fifo_ddr3_in_rd_en),          // input wire rd_en
      .dout         (fifo_ddr3_in_dout),           // output wire [255 : 0] dout
      .full         (),                            // output wire full
      .empty        (),                            // output wire empty
      .almost_empty (fifo_ddr3_in_empty),          // output wire almost_empty
      .rd_data_count(fifo_ddr3_in_rd_data_count),  // output wire [6 : 0] rd_data_count
      .prog_full    (fifo_ddr3_in_full),           // output wire prog_full
      .wr_rst_busy  (),                            // output wire wr_rst_busy
      .rd_rst_busy  ()                             // output wire rd_rst_busy
  );
  fifo_w256_128_r32_1024 fifo_ddr3_out (
      .rst          (fifo_reset),                   // input wire rst
      .wr_clk       (ui_clk),                       // input wire wr_clk
      .rd_clk       (okClk),                        // input wire rd_clk
      .din          (fifo_ddr3_out_din),            // input wire [255 : 0] din
      .wr_en        (fifo_ddr3_out_wr_en),          // input wire wr_en
      .rd_en        (fifo_ddr3_out_rd_en),          // input wire rd_en
      .dout         (fifo_ddr3_out_dout),           // output wire [31 : 0] dout
      .full         (),                             // output wire full
      .almost_full  (fifo_ddr3_out_full),           // output wire almost_full
      .empty        (),                             // output wire empty
      .wr_data_count(fifo_ddr3_out_wr_data_count),  // output wire [6 : 0] wr_data_count
      .prog_empty   (fifo_ddr3_out_empty),          // output wire prog_empty
      .wr_rst_busy  (),                             // output wire wr_rst_busy
      .rd_rst_busy  ()                              // output wire rd_rst_busy
  );
  ddr3_ui u_ddr3_ui (
      .clk              (ui_clk),
      .reset            (ddr3_reset | ui_clk_sync_rst),
      .reads_en         (fifo_ddr3_out_ready),
      .writes_en        (fifo_ddr3_in_ready),
      .calib_done       (init_calib_complete),
      .full             (ui_full),
      .empty            (ui_empty),
      // input fifo
      .ib_re            (fifo_ddr3_in_rd_en),
      .ib_data          (fifo_ddr3_in_dout),
      .ib_count         (fifo_ddr3_in_rd_data_count),
      .ib_valid         (fifo_ddr3_in_ready),
      .ib_empty         (),
      // output fifo
      .ob_we            (fifo_ddr3_out_wr_en),
      .ob_data          (fifo_ddr3_out_din),
      .ob_count         (fifo_ddr3_out_wr_data_count),
      .ob_full          (),
      // mig app interface
      .app_rdy          (app_rdy),
      .app_en           (app_en),
      .app_cmd          (app_cmd),
      .app_addr         (app_addr),
      .app_rd_data      (app_rd_data),
      .app_rd_data_end  (app_rd_data_end),
      .app_rd_data_valid(app_rd_data_valid),
      .app_wdf_rdy      (app_wdf_rdy),
      .app_wdf_wren     (app_wdf_wren),
      .app_wdf_data     (app_wdf_data),
      .app_wdf_end      (app_wdf_end),
      .app_wdf_mask     (app_wdf_mask)
  );
  xem7310_a75_mig u_xem7310_a75_mig (
      // Memory interface ports
      .ddr3_addr          (ddr3_addr),            // output [14:0] ddr3_addr
      .ddr3_ba            (ddr3_ba),              // output [2:0] ddr3_ba
      .ddr3_cas_n         (ddr3_cas_n),           // output ddr3_cas_n
      .ddr3_ck_n          (ddr3_ck_n),            // output [0:0] ddr3_ck_n
      .ddr3_ck_p          (ddr3_ck_p),            // output [0:0] ddr3_ck_p
      .ddr3_cke           (ddr3_cke),             // output [0:0] ddr3_cke
      .ddr3_ras_n         (ddr3_ras_n),           // output ddr3_ras_n
      .ddr3_reset_n       (ddr3_reset_n),         // output ddr3_reset_n
      .ddr3_we_n          (ddr3_we_n),            // output ddr3_we_n
      .ddr3_dq            (ddr3_dq),              // inout [31:0] ddr3_dq
      .ddr3_dqs_n         (ddr3_dqs_n),           // inout [3:0] ddr3_dqs_n
      .ddr3_dqs_p         (ddr3_dqs_p),           // inout [3:0] ddr3_dqs_p
      .init_calib_complete(init_calib_complete),  // output init_calib_complete
      .ddr3_dm            (ddr3_dm),              // output [3:0] ddr3_dm
      .ddr3_odt           (ddr3_odt),             // output [0:0] ddr3_odt
      // Application interface ports
      .app_addr           (app_addr),             // input [28:0] app_addr
      .app_cmd            (app_cmd),              // input [2:0] app_cmd
      .app_en             (app_en),               // input app_en
      .app_wdf_data       (app_wdf_data),         // input [255:0] app_wdf_data
      .app_wdf_end        (app_wdf_end),          // input app_wdf_end
      .app_wdf_wren       (app_wdf_wren),         // input app_wdf_wren
      .app_wdf_mask       (app_wdf_mask),         // input [31:0] app_wdf_mask
      .app_rd_data        (app_rd_data),          // output [255:0] app_rd_data
      .app_rd_data_end    (app_rd_data_end),      // output app_rd_data_end
      .app_rd_data_valid  (app_rd_data_valid),    // output app_rd_data_valid
      .app_rdy            (app_rdy),              // output app_rdy
      .app_wdf_rdy        (app_wdf_rdy),          // output app_wdf_rdy
      .app_sr_req         (1'b0),                 // input app_sr_req
      .app_ref_req        (1'b0),                 // input app_ref_req
      .app_zq_req         (1'b0),                 // input app_zq_req
      .app_sr_active      (),                     // output app_sr_active
      .app_ref_ack        (),                     // output app_ref_ack
      .app_zq_ack         (),                     // output app_zq_ack
      .ui_clk             (ui_clk),               // output ui_clk
      .ui_clk_sync_rst    (ui_clk_sync_rst),      // output ui_clk_sync_rst
      // System Clock Ports
      .sys_clk_i          (sysClk),
      .sys_rst            (ddr3_reset)            // input sys_rst
  );

  // ok interfaces
  // ok pipe reverse byte order
  assign pipe_datain = {
    fifo_ddr3_out_dout[7:0],
    fifo_ddr3_out_dout[15:8],
    fifo_ddr3_out_dout[23:16],
    fifo_ddr3_out_dout[31:24]
  };
  assign pipe_ready = ~fifo_ddr3_out_empty;

  assign pipe2_datain = {
    fifo2_out_dout[7:0],
    fifo2_out_dout[15:8],
    fifo2_out_dout[23:16],
    fifo2_out_dout[31:24]
  };
  assign pipe2_ready = ~fifo2_out_empty;

  okWireOR #(
      .N(2)
  ) wireOR (
      okEH,
      okEHx
  );

  okHost okHI (
      .okUH (okUH),
      .okHU (okHU),
      .okUHU(okUHU),
      .okAA (okAA),
      .okClk(okClk),
      .okHE (okHE),
      .okEH (okEH)
      //   .dna(),
      //   .dna_valid()
  );

  okWireIn wi00 (
      .okHE(okHE),
      .ep_addr(8'h00),
      .ep_dataout(ep00wire)
  );

  okBTPipeOut epA0 (
      .okHE(okHE),
      .okEH(okEHx[64:0]),
      .ep_addr(8'ha0),
      .ep_read(fifo_ddr3_out_rd_en),
      .ep_blockstrobe(),
      .ep_datain(pipe_datain),
      .ep_ready(pipe_ready)
  );

  okBTPipeOut epA1 (
      .okHE(okHE),
      .okEH(okEHx[129:65]),
      .ep_addr(8'ha1),
      .ep_read(fifo2_out_rd_en),
      .ep_blockstrobe(),
      .ep_datain(pipe2_datain),
      .ep_ready(pipe2_ready)
  );

endmodule

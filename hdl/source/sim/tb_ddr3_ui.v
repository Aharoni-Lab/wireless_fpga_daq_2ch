`timescale 1ns / 1ps

// Unit testbench for the two-channel DDR3 arbiter.
//
// Why this exists separately from tb_USBInterface: MIG calibration does not
// converge against the Micron model in this project (tWLS violations on DQS,
// init_calib_complete never asserts), so the full testbench can only run with
// CH2_ONLY=1 and has never been able to exercise the DDR3 path at all. Putting
// channel 2 behind the MIG would therefore have left the new arbitration logic
// with no simulation coverage whatsoever. This replaces the MIG with a
// behavioural model of its user interface and tests the part that is actually
// new.
//
// What it checks:
//   1. Both channels round-trip their data through DDR3 intact and in order.
//   2. No cross-channel contamination -- each word carries a channel tag, and
//      a word arriving on the wrong sink fails the test. This is the failure
//      the shared ob_data bus and the shared address counter would produce.
//   3. Ring wrap and the full/empty conditions, by shrinking RING_ADDR_BITS so
//      both rings wrap many times in a few microseconds.
//   4. Round-robin fairness: with both channels permanently backlogged,
//      neither may take more than a small majority of the bursts. A fixed
//      priority would show up here as one channel taking everything.
//
// Run it:
//   xvlog ../design/ddr3/ddr3_ui.v tb_ddr3_ui.v
//   xelab -debug typical work.tb_ddr3_ui -s tb_ddr3_ui_sim
//   xsim tb_ddr3_ui_sim -runall

module tb_ddr3_ui;

  // 2^5 words / 8 per burst = 4 burst slots per ring. Deliberately tiny: with
  // NWORDS bursts pushed through, each ring wraps tens of times and spends
  // most of the run at or near full, which is the state the design will sit in
  // whenever the host stalls.
  localparam RING_ADDR_BITS = 5;
  localparam NWORDS = 200;  // bursts per channel
  localparam RD_LAT = 5;  // app_rd_data_valid latency, cycles
  localparam TIMEOUT_CYCLES = 200000;

  reg clk = 1'b0;
  reg reset = 1'b1;
  always #5 clk = ~clk;  // 100 MHz

  //=============== Stimulus and expected data ===============
  //
  // Every 256-bit word is one 32-bit value repeated eight times. The top half
  // of that value is the channel tag, the bottom half the sequence number, so
  // a word that arrives on the wrong channel or out of order is visible on
  // inspection and not just as a miscompare.
  function [255:0] word_for(input integer ch, input integer idx);
    reg [31:0] v;
    begin
      v = (ch == 0 ? 32'hA0A0_0000 : 32'hA1A1_0000) | idx[15:0];
      word_for = {8{v}};
    end
  endfunction

  //=============== Channel sources (stand in for fifo*_ddr3_in) ===============

  integer src_ptr[0:1];
  reg [255:0] ib_data_r[0:1];
  reg ib_valid_r[0:1];
  wire [6:0] ib_count[0:1];
  wire ib_re[0:1];

  // The real design ties ib_valid to the input FIFO's data-available flag,
  // which is high in the cycle the DUT samples it. Modelling it as a true
  // one-cycle-after-read valid is the same thing from the DUT's point of view
  // and cannot produce a false hang when the source drains.
  always @(posedge clk) begin
    ib_valid_r[0] <= ib_re[0];
    ib_valid_r[1] <= ib_re[1];
    if (ib_re[0]) begin
      ib_data_r[0] <= word_for(0, src_ptr[0]);
      src_ptr[0]   <= src_ptr[0] + 1;
    end
    if (ib_re[1]) begin
      ib_data_r[1] <= word_for(1, src_ptr[1]);
      src_ptr[1]   <= src_ptr[1] + 1;
    end
  end

  // Plenty of data available, until the source runs out.
  assign ib_count[0] = (src_ptr[0] < NWORDS) ? 7'd64 : 7'd0;
  assign ib_count[1] = (src_ptr[1] < NWORDS) ? 7'd64 : 7'd0;

  //=============== Channel sinks (stand in for fifo*_ddr3_out) ===============

  integer rcv_cnt[0:1];
  reg [255:0] rcv[0:1][0:NWORDS-1];
  integer errors;

  wire [255:0] ob_data;
  wire ob_we[0:1];

  always @(posedge clk) begin
    if (!reset) begin
      if (ob_we[0]) begin
        if (rcv_cnt[0] < NWORDS) rcv[0][rcv_cnt[0]] <= ob_data;
        rcv_cnt[0] <= rcv_cnt[0] + 1;
      end
      if (ob_we[1]) begin
        if (rcv_cnt[1] < NWORDS) rcv[1][rcv_cnt[1]] <= ob_data;
        rcv_cnt[1] <= rcv_cnt[1] + 1;
      end
      // Both write enables in one cycle would mean one burst landing in two
      // channels at once -- impossible by construction, so assert it.
      if (ob_we[0] && ob_we[1]) begin
        $display("FAIL: ob_we and ob2_we asserted in the same cycle");
        errors = errors + 1;
      end
    end
  end

  // Fairness has to be sampled while both channels are still competing. The
  // final counts are always NWORDS for both -- once the greedy channel's
  // source drains, the starved one gets the whole controller and catches up --
  // so comparing those would pass even under a fixed priority. Snapshot both
  // counts the moment the first channel finishes instead: that is the point at
  // which a fair arbiter has them nearly level.
  reg snapped = 1'b0;
  integer snap[0:1];
  always @(posedge clk) begin
    if (!reset && !snapped && (rcv_cnt[0] >= NWORDS || rcv_cnt[1] >= NWORDS)) begin
      snapped <= 1'b1;
      snap[0] <= rcv_cnt[0];
      snap[1] <= rcv_cnt[1];
    end
  end

  //=============== Ready/valid into the DUT ===============

  wire full, empty, full2, empty2;
  // Exactly how USBInterface.v forms these: writes when the source has data
  // and the ring has room, reads when the ring has data and the sink has room.
  // The sinks here never fill, so reads are limited only by the ring.
  wire writes_en = (src_ptr[0] < NWORDS) & ~full;
  wire reads_en = ~empty;
  wire writes2_en = (src_ptr[1] < NWORDS) & ~full2;
  wire reads2_en = ~empty2;

  //=============== Behavioural MIG user interface ===============
  //
  // Not a DDR3 model: a model of what the MIG presents to ddr3_ui. It stalls
  // app_rdy and app_wdf_rdy pseudo-randomly so the retry paths in s_write_4
  // and s_read_1 are exercised, which is where a per-channel address would be
  // corrupted if the arbiter dropped cur_ch mid-burst.
  //
  // Write data is sampled at command time rather than through a staging FIFO.
  // ddr3_ui holds app_wdf_data in a register from s_write_1 until the command
  // is accepted, so the two are equivalent here, and the wdf handshake itself
  // is unchanged code.

  localparam ADDR_SPAN = 1 << (RING_ADDR_BITS + 1);

  wire [ 28:0] app_addr;
  wire [  2:0] app_cmd;
  wire         app_en;
  wire [255:0] app_wdf_data;
  wire         app_wdf_wren;
  wire         app_wdf_end;

  reg  [255:0] mem     [0:ADDR_SPAN-1];
  reg          app_rdy = 1'b1;
  reg          app_wdf_rdy = 1'b1;
  reg [31:0] lfsr = 32'hACE1_2345;

  always @(posedge clk) begin
    lfsr        <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    app_rdy     <= (lfsr[2:0] != 3'b000);  // ready ~7/8 of cycles
    app_wdf_rdy <= (lfsr[6:4] != 3'b000);
  end

  reg [255:0] rd_pipe[0:RD_LAT-1];
  reg rd_val[0:RD_LAT-1];
  integer k;

  // Addresses outside the two rings mean the arbiter computed a bad address --
  // the most likely way a two-ring split goes wrong.
  wire addr_in_range = (app_addr < ADDR_SPAN);

  always @(posedge clk) begin
    if (app_en && app_rdy && !addr_in_range) begin
      $display("FAIL: app_addr %h outside both rings (span %0d)", app_addr, ADDR_SPAN);
      errors = errors + 1;
    end
    if (app_en && app_rdy && app_cmd == 3'b000 && addr_in_range) begin
      mem[app_addr] <= app_wdf_data;
    end
    for (k = RD_LAT - 1; k > 0; k = k - 1) begin
      rd_pipe[k] <= rd_pipe[k-1];
      rd_val[k]  <= rd_val[k-1];
    end
    rd_val[0]  <= (app_en && app_rdy && app_cmd == 3'b001 && addr_in_range);
    rd_pipe[0] <= addr_in_range ? mem[app_addr] : {256{1'bx}};
  end

  wire [255:0] app_rd_data = rd_pipe[RD_LAT-1];
  wire app_rd_data_valid = rd_val[RD_LAT-1];

  //=============== DUT ===============

  ddr3_ui #(
      .RING_ADDR_BITS(RING_ADDR_BITS)
  ) dut (
      .clk              (clk),
      .reset            (reset),
      .calib_done       (1'b1),
      // channel 1
      .writes_en        (writes_en),
      .reads_en         (reads_en),
      .ib_re            (ib_re[0]),
      .ib_data          (ib_data_r[0]),
      .ib_count         (ib_count[0]),
      .ib_valid         (ib_valid_r[0]),
      .ib_empty         (1'b0),
      .ob_we            (ob_we[0]),
      .ob_count         (7'd0),          // sink never fills
      .ob_full          (1'b0),
      .full             (full),
      .empty            (empty),
      // channel 2
      .writes2_en       (writes2_en),
      .reads2_en        (reads2_en),
      .ib2_re           (ib_re[1]),
      .ib2_data         (ib_data_r[1]),
      .ib2_count        (ib_count[1]),
      .ib2_valid        (ib_valid_r[1]),
      .ib2_empty        (1'b0),
      .ob2_we           (ob_we[1]),
      .ob2_count        (7'd0),
      .ob2_full         (1'b0),
      .full2            (full2),
      .empty2           (empty2),
      // shared
      .ob_data          (ob_data),
      // mig
      .app_rdy          (app_rdy),
      .app_en           (app_en),
      .app_cmd          (app_cmd),
      .app_addr         (app_addr),
      .app_rd_data      (app_rd_data),
      .app_rd_data_end  (1'b1),
      .app_rd_data_valid(app_rd_data_valid),
      .app_wdf_rdy      (app_wdf_rdy),
      .app_wdf_wren     (app_wdf_wren),
      .app_wdf_data     (app_wdf_data),
      .app_wdf_end      (app_wdf_end),
      .app_wdf_mask     ()
  );

  //=============== Address-range check, per channel ===============
  //
  // Beyond "inside the device": channel 1 must never touch channel 2's ring
  // and vice versa. This is the check that a shared address counter, or a
  // cur_ch that changes mid-burst, would fail.
  wire ch_of_addr = app_addr[RING_ADDR_BITS];
  always @(posedge clk) begin
    if (!reset && app_en && app_rdy && addr_in_range) begin
      if (ch_of_addr !== dut.cur_ch) begin
        $display("FAIL @%0t: burst for channel %0d addressed ring %0d (addr %h)", $time,
                 dut.cur_ch, ch_of_addr, app_addr);
        errors = errors + 1;
      end
    end
  end

  //=============== Run ===============

  integer c, n, cycles;
  initial begin
    errors     = 0;
    src_ptr[0] = 0;
    src_ptr[1] = 0;
    rcv_cnt[0] = 0;
    rcv_cnt[1] = 0;
    ib_valid_r[0] = 1'b0;
    ib_valid_r[1] = 1'b0;
    for (k = 0; k < RD_LAT; k = k + 1) rd_val[k] = 1'b0;
    for (k = 0; k < ADDR_SPAN; k = k + 1) mem[k] = 256'h0;

    repeat (20) @(posedge clk);
    reset <= 1'b0;

    // Run until both channels have delivered everything, or give up.
    cycles = 0;
    while ((rcv_cnt[0] < NWORDS || rcv_cnt[1] < NWORDS) && cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (cycles >= TIMEOUT_CYCLES) begin
      $display("FAIL: timed out -- ch1 got %0d/%0d, ch2 got %0d/%0d", rcv_cnt[0], NWORDS,
               rcv_cnt[1], NWORDS);
      errors = errors + 1;
    end

    repeat (10) @(posedge clk);

    //=============== Checks ===============

    for (c = 0; c < 2; c = c + 1) begin
      for (n = 0; n < NWORDS; n = n + 1) begin
        if (n < rcv_cnt[c] && rcv[c][n] !== word_for(c, n)) begin
          if (errors < 20)
            $display("FAIL: ch%0d word %0d: got %h expected %h", c + 1, n, rcv[c][n][31:0],
                     word_for(c, n));
          errors = errors + 1;
        end
      end
    end

    // Fairness, measured at the snapshot: both channels are backlogged up to
    // that point, so a fair arbiter has delivered them at nearly the same
    // rate. Anything worse than a 2:1 split means round-robin is not working.
    if (!snapped) begin
      $display("FAIL: never reached the fairness snapshot");
      errors = errors + 1;
    end else if (snap[0] > 2 * snap[1] || snap[1] > 2 * snap[0]) begin
      $display("FAIL: unfair arbitration -- at first completion, ch1 %0d bursts, ch2 %0d bursts",
               snap[0], snap[1]);
      errors = errors + 1;
    end

    $display("---------------------------------------------");
    $display("ch1 delivered %0d/%0d words", rcv_cnt[0], NWORDS);
    $display("ch2 delivered %0d/%0d words", rcv_cnt[1], NWORDS);
    $display("at first completion: ch1 %0d, ch2 %0d", snap[0], snap[1]);
    $display("ring slots per channel: %0d", (1 << RING_ADDR_BITS) / 8);
    if (errors == 0) $display("PASS");
    else $display("FAIL: %0d error(s)", errors);
    $display("---------------------------------------------");
    $finish;
  end

endmodule

`timescale 1ns / 1ps

// DDR3 user-interface arbiter for two capture channels.
//
// One MIG controller, two independent ring buffers. Each channel presents the
// same pair of FIFOs channel 1 always had -- a 32->256 bit input FIFO filled on
// its recovered clock, and a 256->32 bit output FIFO drained by its USB pipe --
// and this block time-shares the single MIG user interface between them.
//
// The burst machinery below s_idle is unchanged from the single-channel
// version; what is new is that s_idle now chooses between four jobs instead of
// two, and that every address, counter and handshake is indexed by the channel
// that won.
//
// Address map. Each channel gets a contiguous ring of its own, selected by the
// bit above RING_ADDR_BITS:
//
//   channel 1   app_addr [0 .. 2^RING_ADDR_BITS)
//   channel 2   app_addr [2^RING_ADDR_BITS .. 2^(RING_ADDR_BITS+1))
//
// app_addr counts 4-byte words, so RING_ADDR_BITS = 26 is 256 MiB per channel,
// 512 MiB in total on a 1 GiB board (2 x MT41K256M16 at DataWidth 32). That is
// deliberately short of the device: the ring only has to outlast a host stall,
// and 256 MiB is about four minutes at 8.33 Mbit/s. Shrinking it is a one-line
// change if the address mapping ever turns out to be narrower than assumed.

module ddr3_ui #(
    // Overridden only by tb_ddr3_ui, which shrinks the rings to a handful of
    // bursts so ring wrap and the full/empty conditions happen in microseconds
    // instead of hours. Nothing in the design changes it.
    parameter RING_ADDR_BITS = 26  // 2^26 words x 4 byte = 256 MiB per channel
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         calib_done,
    // Channel 1
    input  wire         writes_en,
    input  wire         reads_en,
    output reg          ib_re,
    input  wire [255:0] ib_data,
    input  wire [  6:0] ib_count,
    input  wire         ib_valid,
    input  wire         ib_empty,
    output reg          ob_we,
    input  wire [  6:0] ob_count,
    input  wire         ob_full,
    output wire         full,
    output wire         empty,
    // Channel 2
    input  wire         writes2_en,
    input  wire         reads2_en,
    output reg          ib2_re,
    input  wire [255:0] ib2_data,
    input  wire [  6:0] ib2_count,
    input  wire         ib2_valid,
    input  wire         ib2_empty,
    output reg          ob2_we,
    input  wire [  6:0] ob2_count,
    input  wire         ob2_full,
    output wire         full2,
    output wire         empty2,
    // Read data, shared. Both output FIFOs see the same bus; only the write
    // enable above says which of them is being filled.
    output reg  [255:0] ob_data,
    // app interface
    input  wire         app_rdy,
    output reg          app_en,
    output reg  [  2:0] app_cmd,
    output reg  [ 28:0] app_addr,
    input  wire [255:0] app_rd_data,
    input  wire         app_rd_data_end,
    input  wire         app_rd_data_valid,
    input  wire         app_wdf_rdy,
    output reg          app_wdf_wren,
    output reg  [255:0] app_wdf_data,
    output reg          app_wdf_end,
    output wire [ 31:0] app_wdf_mask
);

  localparam FIFO_SIZE = 128;
  localparam BURST_UI_WORD_COUNT = 2'd1; //(WORD_SIZE*BURST_MODE/UI_SIZE) = BURST_UI_WORD_COUNT : 32*8/256 = 1
  localparam ADDRESS_INCREMENT = 29'd8;  // UI Address is a word address. BL8 Burst Mode = 8.

  // Ring offsets, not absolute addresses: they wrap inside their own ring, and
  // the channel bit is added only when the address is handed to the MIG. 2^26
  // is a multiple of the burst increment, so the wrap needs no special case.
  localparam [RING_ADDR_BITS-1:0] RING_STEP = ADDRESS_INCREMENT[RING_ADDR_BITS-1:0];

  reg [RING_ADDR_BITS-1:0] wr_off[0:1];
  reg [RING_ADDR_BITS-1:0] rd_off[0:1];

  reg write_mode[0:1];
  reg read_mode[0:1];
  reg reset_d;
  reg cur_ch;  // channel the in-flight burst belongs to
  reg [1:0] burst_count;

  assign app_wdf_mask = 32'h00000000;

  assign full   = ((wr_off[0] + RING_STEP) == rd_off[0]);
  assign empty  = (wr_off[0] == rd_off[0]);
  assign full2  = ((wr_off[1] + RING_STEP) == rd_off[1]);
  assign empty2 = (wr_off[1] == rd_off[1]);

  always @(posedge clk) write_mode[0] <= writes_en;
  always @(posedge clk) read_mode[0] <= reads_en;
  always @(posedge clk) write_mode[1] <= writes2_en;
  always @(posedge clk) read_mode[1] <= reads2_en;
  always @(posedge clk) reset_d <= reset;

  // Per-channel input multiplexing. Only ever read while cur_ch is stable,
  // which it is from s_write_0 onward: s_idle latches it in the same cycle it
  // leaves s_idle.
  wire [255:0] ib_data_sel = cur_ch ? ib2_data : ib_data;
  wire ib_valid_sel = cur_ch ? ib2_valid : ib_valid;

  function [28:0] ring_addr(input ch, input [RING_ADDR_BITS-1:0] off);
    ring_addr = {{(29 - RING_ADDR_BITS - 1) {1'b0}}, ch, off};
  endfunction

  //=============== Arbitration ===============
  //
  // Four jobs, encoded {channel, is_read}, served round-robin from a rotating
  // pointer. Round-robin rather than the fixed write-then-read priority the
  // single-channel version used: with one client that priority was harmless,
  // but with two it would let one channel's writes starve the other channel
  // entirely, which is the exact failure this block exists to prevent.
  //
  // writes_en already carries ~full and reads_en already carries ~empty -- the
  // top level folds them in, as it did before -- so the conditions here only
  // add what this block can see: calibration, and room at the far end of the
  // burst.
  wire [3:0] job_ready;
  assign job_ready[0] = calib_done & write_mode[0] & (ib_count >= BURST_UI_WORD_COUNT);
  assign job_ready[1] = calib_done & read_mode[0] & (ob_count < (FIFO_SIZE-2-BURST_UI_WORD_COUNT));
  assign job_ready[2] = calib_done & write_mode[1] & (ib2_count >= BURST_UI_WORD_COUNT);
  assign job_ready[3] = calib_done & read_mode[1] & (ob2_count < (FIFO_SIZE-2-BURST_UI_WORD_COUNT));

  reg [1:0] rr_ptr;
  reg [1:0] grant;
  reg grant_valid;
  reg [1:0] scan_idx;
  integer i;
  always @* begin
    grant       = 2'd0;
    grant_valid = 1'b0;
    for (i = 0; i < 4; i = i + 1) begin
      scan_idx = rr_ptr + i[1:0];  // 2-bit add wraps mod 4
      if (!grant_valid && job_ready[scan_idx]) begin
        grant       = scan_idx;
        grant_valid = 1'b1;
      end
    end
  end

  integer state;
  localparam s_idle    = 0,
           s_write_0 = 10,
           s_write_1 = 11,
           s_write_2 = 12,
           s_write_3 = 13,
           s_write_4 = 14,
           s_read_0  = 20,
           s_read_1  = 21,
           s_read_2  = 22,
           s_read_3  = 23,
           s_read_4  = 24;
  always @(posedge clk) begin
    if (reset_d) begin
      state        <= s_idle;
      burst_count  <= 2'b00;
      wr_off[0]    <= 0;
      rd_off[0]    <= 0;
      wr_off[1]    <= 0;
      rd_off[1]    <= 0;
      cur_ch       <= 1'b0;
      rr_ptr       <= 2'd0;
      app_en       <= 1'b0;
      app_cmd      <= 3'b0;
      app_addr     <= 29'b0;
      app_wdf_wren <= 1'b0;
      app_wdf_end  <= 1'b0;
    end else begin
      app_en       <= 1'b0;
      app_wdf_wren <= 1'b0;
      app_wdf_end  <= 1'b0;
      ib_re        <= 1'b0;
      ib2_re       <= 1'b0;
      ob_we        <= 1'b0;
      ob2_we       <= 1'b0;


      case (state)
        s_idle: begin
          burst_count <= BURST_UI_WORD_COUNT - 1;
          if (grant_valid) begin
            cur_ch <= grant[1];
            rr_ptr <= grant + 2'd1;
            if (grant[0]) begin
              app_addr <= ring_addr(grant[1], rd_off[grant[1]]);
              state    <= s_read_0;
            end else begin
              app_addr <= ring_addr(grant[1], wr_off[grant[1]]);
              state    <= s_write_0;
            end
          end
        end

        s_write_0: begin
          state <= s_write_1;
          if (cur_ch) ib2_re <= 1'b1;
          else ib_re <= 1'b1;
        end

        s_write_1: begin
          if (ib_valid_sel == 1) begin
            app_wdf_data <= ib_data_sel;
            state <= s_write_2;
          end
        end

        s_write_2: begin
          if (app_wdf_rdy == 1'b1) begin
            state <= s_write_3;
          end
        end

        s_write_3: begin
          app_wdf_wren <= 1'b1;
          if (burst_count == 2'd0) begin
            app_wdf_end <= 1'b1;
          end
          if ((app_wdf_rdy == 1'b1) & (burst_count == 2'd0)) begin
            app_en  <= 1'b1;
            app_cmd <= 3'b000;
            state   <= s_write_4;
          end else if (app_wdf_rdy == 1'b1) begin
            burst_count <= burst_count - 1'b1;
            state <= s_write_0;
          end
        end

        s_write_4: begin
          if (app_rdy == 1'b1) begin
            wr_off[cur_ch] <= wr_off[cur_ch] + RING_STEP;
            state <= s_idle;
          end else begin
            app_en  <= 1'b1;
            app_cmd <= 3'b000;
          end
        end


        s_read_0: begin
          app_en  <= 1'b1;
          app_cmd <= 3'b001;
          state   <= s_read_1;
        end

        s_read_1: begin
          if (app_rdy == 1'b1) begin
            rd_off[cur_ch] <= rd_off[cur_ch] + RING_STEP;
            state <= s_read_2;
          end else begin
            app_en  <= 1'b1;
            app_cmd <= 3'b001;
          end
        end

        s_read_2: begin
          if (app_rd_data_valid == 1'b1) begin
            ob_data <= app_rd_data;
            if (cur_ch) ob2_we <= 1'b1;
            else ob_we <= 1'b1;
            if (burst_count == 2'd0) begin
              state <= s_idle;
            end else begin
              burst_count <= burst_count - 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule

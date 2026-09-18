`timescale 1ns / 1ps

module ddr3_ui (
    input  wire         clk,
    input  wire         reset,
    input  wire         writes_en,
    input  wire         reads_en,
    input  wire         calib_done,
    // DDR Input Buffer (ib_)
    output reg          ib_re,
    input  wire [255:0] ib_data,
    input  wire [  6:0] ib_count,
    input  wire         ib_valid,
    input  wire         ib_empty,
    // DDR Output Buffer (ob_)
    output reg          ob_we,
    output reg  [255:0] ob_data,
    input  wire [  6:0] ob_count,
    input  wire         ob_full,
    // UI status
    output wire         full,
    output wire         empty,
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

  reg [28:0] cmd_byte_addr_wr;
  reg [28:0] cmd_byte_addr_rd;
  reg [ 1:0] burst_count;

  reg        write_mode;
  reg        read_mode;
  reg        reset_d;

  // assign app_wdf_mask = 16'h0000;
  assign app_wdf_mask = 32'h00000000;

  assign full = (cmd_byte_addr_wr + ADDRESS_INCREMENT) == cmd_byte_addr_rd;
  assign empty = cmd_byte_addr_wr == cmd_byte_addr_rd;

  always @(posedge clk) write_mode <= writes_en;
  always @(posedge clk) read_mode <= reads_en;
  always @(posedge clk) reset_d <= reset;


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
      state            <= s_idle;
      burst_count      <= 2'b00;
      cmd_byte_addr_wr <= 0;
      cmd_byte_addr_rd <= 0;
      app_en           <= 1'b0;
      app_cmd          <= 3'b0;
      // app_addr         <= 28'b0;
      app_addr         <= 29'b0;
      app_wdf_wren     <= 1'b0;
      app_wdf_end      <= 1'b0;
    end else begin
      app_en       <= 1'b0;
      app_wdf_wren <= 1'b0;
      app_wdf_end  <= 1'b0;
      ib_re        <= 1'b0;
      ob_we        <= 1'b0;


      case (state)
        s_idle: begin
          burst_count <= BURST_UI_WORD_COUNT - 1;
          // Only start writing when initialization done
          // Check to ensure that the input buffer has enough data for
          // a burst
          if (calib_done == 1 && write_mode == 1 && (ib_count >= BURST_UI_WORD_COUNT)) begin
            app_addr <= cmd_byte_addr_wr;
            state <= s_write_0;
            // Check to ensure that the output buffer has enough space
            // for a burst
          end else if (calib_done==1 && read_mode==1 && (ob_count<(FIFO_SIZE-2-BURST_UI_WORD_COUNT) ) ) begin
            app_addr <= cmd_byte_addr_rd;
            state <= s_read_0;
          end
        end

        s_write_0: begin
          state <= s_write_1;
          ib_re <= 1'b1;
        end

        s_write_1: begin
          if (ib_valid == 1) begin
            app_wdf_data <= ib_data;
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
            cmd_byte_addr_wr <= cmd_byte_addr_wr + ADDRESS_INCREMENT;
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
            cmd_byte_addr_rd <= cmd_byte_addr_rd + ADDRESS_INCREMENT;
            state <= s_read_2;
          end else begin
            app_en  <= 1'b1;
            app_cmd <= 3'b001;
          end
        end

        s_read_2: begin
          if (app_rd_data_valid == 1'b1) begin
            ob_data <= app_rd_data;
            ob_we   <= 1'b1;
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

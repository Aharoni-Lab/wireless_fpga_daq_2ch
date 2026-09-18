`include "recclk.v"
`include "buf2.v"

module mandec #(
    parameter integer NDELAY = 32  // obsolete
) (
    input wire i_clk,  // high frequency clock
    input wire i_data,  // input manchester encoded data
    input wire i_reset,  // active low reset
    output wire o_clk,  // recovered clock
    output wire [1:0] o_data,  // recovered NRZ data
    output wire dbg_man_dly,
    output wire dbg_rec_clk
);
  supply1 _vdd;
  wire clk_rec;
  wire data_dly;

  reg read_clk = 1'b0;
  reg read_switch;
  assign o_clk = ~i_reset | (read_clk ^ read_switch);

  //Debug signals
  assign dbg_man_dly = data_dly;
  assign dbg_rec_clk = clk_rec;

  recclk #(NDELAY) rec (
      .i_clk(i_clk),
      .i_data(i_data),
      .i_reset(i_reset),
      .o_recclk(clk_rec)
  );
  buf2 b (
      .i_clk  (clk_rec),
      .i_reset(i_reset),
      .i_data (data_dly),
      .o_data (o_data)
  );
  c_shift_ram_0 dly_data (
      .D  (i_data),   // input wire [0 : 0] D
      .CLK(i_clk),    // input wire CLK
      .Q  (data_dly)  // output wire [0 : 0] Q
  );

  always @(negedge clk_rec) begin
    read_clk <= ~read_clk;
    if (o_data == 2'b00 | o_data == 2'b11) begin
      case (read_clk)
        1'b0: read_switch <= 1'b1;
        1'b1: read_switch <= 1'b0;
        default: read_switch <= 1'b0;
      endcase
    end
  end

endmodule

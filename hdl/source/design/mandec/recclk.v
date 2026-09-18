`include "delay_osc.v"

module recclk #(
    parameter integer NDELAY = 2  // obsolete
) (
    input  wire i_clk,    // high frequency clock
    input  wire i_data,   // input manchester data
    input  wire i_reset,  // active low reset
    output wire o_recclk  // recovered clock
);
  wire x1;
  wire x2;
  wire x3;
  wire x4;

  c_shift_ram_0 dly (
      .D(i_data),  // input wire [0 : 0] D
      .CLK(i_clk),  // input wire CLK
      .Q(x1)  // output wire [0 : 0] Q
  );

  assign x2 = ~i_data;
  assign x3 = x1 ^ x2;
  assign x4 = ~(1'b1 & x3);
  delay_osc #(NDELAY) osc (
      .i_clk  (i_clk),
      .i_data (x4),
      .i_reset(i_reset),
      .o_data (o_recclk)
  );

endmodule

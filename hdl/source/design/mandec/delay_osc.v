module delay_osc #(
    parameter integer NDELAY = 2  // obsolete
) (
    input  wire i_clk,    // input high frequency clock
    input  wire i_data,   // input line
    input  wire i_reset,  // active low reset
    output wire o_data    // output data

);
  wire dly_in;
  wire dly_out;
  assign dly_in = ~(i_data | dly_out);
  assign o_data = dly_out;
  c_shift_ram_0 dly (
      .D  (dly_in),  // input wire [0 : 0] D
      .CLK(i_clk),   // input wire CLK
      .Q  (dly_out)  // output wire [0 : 0] Q
  );
endmodule

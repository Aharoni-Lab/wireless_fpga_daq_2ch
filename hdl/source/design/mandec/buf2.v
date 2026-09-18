module buf2 (
    input i_clk,  // clock for buffer update
    input i_data,  // current input bit
    input i_reset,  // active low reset
    output reg [1:0] o_data  // output two bit buffer
);
  reg data_last = 0;
  always @(posedge i_clk) begin
    o_data[1] <= data_last & i_reset;
    o_data[0] <= i_data & i_reset;
    data_last <= i_data & i_reset;
  end
endmodule

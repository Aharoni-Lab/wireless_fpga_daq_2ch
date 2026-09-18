//------------------------------------------------------------------------
// okWireOut
//
// This module simulates the "Wire Out" endpoint.
//
//------------------------------------------------------------------------
// Copyright (c) 2005-2022 Opal Kelly Incorporated
// $Rev$ $Date$
//------------------------------------------------------------------------
`default_nettype none
`timescale 1ns / 1ps

module okWireOut(
	input  wire [112:0] okHE,
	output wire [64:0]  okEH,
	input  wire [7:0]   ep_addr,
	input  wire [31:0]  ep_datain
	);

`include "parameters.vh" 
`include "mappings.vh"

reg  [31:0] wirehold;

assign okEH[okEH_DATAH:okEH_DATAL] = (ti_addr == ep_addr) ? (wirehold) : (0);
assign okEH[okEH_READY]            = 0;
assign okEH[okEH_REGREADDATAH:okEH_REGREADDATAL] = 32'b0;

always @(posedge ti_clk) begin
	if (ti_reset == 1)
		wirehold <= 0;
	else if (ti_wireupdate == 1)
		wirehold <= ep_datain;
end

initial begin
	if ((ep_addr < 8'h20) || (ep_addr > 8'h3F)) begin
		$error("okWireOut endpoint address outside valid range, must be between 0x20 and 0x3F");
		$finish;
	end
end

endmodule

`default_nettype wire
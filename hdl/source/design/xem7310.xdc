############################################################################
# XEM7310 - Xilinx constraints file
#
# Pin mappings for the XEM7310.  Use this as a template and comment out 
# the pins that are not used in your design.  (By default, map will fail
# if this file contains constraints for signals not in your design).
#
# Copyright (c) 2004-2016 Opal Kelly Incorporated
############################################################################

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS True [current_design]

############################################################################
## FrontPanel Host Interface
############################################################################
set_property PACKAGE_PIN Y19 [get_ports {okHU[0]}]
set_property PACKAGE_PIN R18 [get_ports {okHU[1]}]
set_property PACKAGE_PIN R16 [get_ports {okHU[2]}]
set_property SLEW FAST [get_ports {okHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okHU[*]}]

set_property PACKAGE_PIN W19 [get_ports {okUH[0]}]
set_property PACKAGE_PIN V18 [get_ports {okUH[1]}]
set_property PACKAGE_PIN U17 [get_ports {okUH[2]}]
set_property PACKAGE_PIN W17 [get_ports {okUH[3]}]
set_property PACKAGE_PIN T19 [get_ports {okUH[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUH[*]}]

set_property PACKAGE_PIN AB22 [get_ports {okUHU[0]}]
set_property PACKAGE_PIN AB21 [get_ports {okUHU[1]}]
set_property PACKAGE_PIN Y22 [get_ports {okUHU[2]}]
set_property PACKAGE_PIN AA21 [get_ports {okUHU[3]}]
set_property PACKAGE_PIN AA20 [get_ports {okUHU[4]}]
set_property PACKAGE_PIN W22 [get_ports {okUHU[5]}]
set_property PACKAGE_PIN W21 [get_ports {okUHU[6]}]
set_property PACKAGE_PIN T20 [get_ports {okUHU[7]}]
set_property PACKAGE_PIN R19 [get_ports {okUHU[8]}]
set_property PACKAGE_PIN P19 [get_ports {okUHU[9]}]
set_property PACKAGE_PIN U21 [get_ports {okUHU[10]}]
set_property PACKAGE_PIN T21 [get_ports {okUHU[11]}]
set_property PACKAGE_PIN R21 [get_ports {okUHU[12]}]
set_property PACKAGE_PIN P21 [get_ports {okUHU[13]}]
set_property PACKAGE_PIN R22 [get_ports {okUHU[14]}]
set_property PACKAGE_PIN P22 [get_ports {okUHU[15]}]
set_property PACKAGE_PIN R14 [get_ports {okUHU[16]}]
set_property PACKAGE_PIN W20 [get_ports {okUHU[17]}]
set_property PACKAGE_PIN Y21 [get_ports {okUHU[18]}]
set_property PACKAGE_PIN P17 [get_ports {okUHU[19]}]
set_property PACKAGE_PIN U20 [get_ports {okUHU[20]}]
set_property PACKAGE_PIN N17 [get_ports {okUHU[21]}]
set_property PACKAGE_PIN N14 [get_ports {okUHU[22]}]
set_property PACKAGE_PIN V20 [get_ports {okUHU[23]}]
set_property PACKAGE_PIN P16 [get_ports {okUHU[24]}]
set_property PACKAGE_PIN T18 [get_ports {okUHU[25]}]
set_property PACKAGE_PIN V19 [get_ports {okUHU[26]}]
set_property PACKAGE_PIN AB20 [get_ports {okUHU[27]}]
set_property PACKAGE_PIN P15 [get_ports {okUHU[28]}]
set_property PACKAGE_PIN V22 [get_ports {okUHU[29]}]
set_property PACKAGE_PIN U18 [get_ports {okUHU[30]}]
set_property PACKAGE_PIN AB18 [get_ports {okUHU[31]}]
set_property SLEW FAST [get_ports {okUHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUHU[*]}]

set_property PACKAGE_PIN N13 [get_ports {okAA}]
set_property IOSTANDARD LVCMOS18 [get_ports {okAA}]


create_clock -name okUH0 -period 9.920 [get_ports {okUH[0]}]

set_input_delay -add_delay -max -clock [get_clocks {okUH0}]  8.000 [get_ports {okUH[*]}]
set_input_delay -add_delay -min -clock [get_clocks {okUH0}] 10.000 [get_ports {okUH[*]}]
set_multicycle_path -setup -from [get_ports {okUH[*]}] 2

set_input_delay -add_delay -max -clock [get_clocks {okUH0}]  8.000 [get_ports {okUHU[*]}]
set_input_delay -add_delay -min -clock [get_clocks {okUH0}]  2.000 [get_ports {okUHU[*]}]
set_multicycle_path -setup -from [get_ports {okUHU[*]}] 2

set_output_delay -add_delay -max -clock [get_clocks {okUH0}]  2.000 [get_ports {okHU[*]}]
set_output_delay -add_delay -min -clock [get_clocks {okUH0}]  -0.500 [get_ports {okHU[*]}]

set_output_delay -add_delay -max -clock [get_clocks {okUH0}]  2.000 [get_ports {okUHU[*]}]
set_output_delay -add_delay -min -clock [get_clocks {okUH0}]  -0.500 [get_ports {okUHU[*]}]

# LEDs #####################################################################
# set_property PACKAGE_PIN A13 [get_ports {led[0]}]
# set_property PACKAGE_PIN B13 [get_ports {led[1]}]
# set_property PACKAGE_PIN A14 [get_ports {led[2]}]
# set_property PACKAGE_PIN A15 [get_ports {led[3]}]
# set_property PACKAGE_PIN B15 [get_ports {led[4]}]
# set_property PACKAGE_PIN A16 [get_ports {led[5]}]
# set_property PACKAGE_PIN B16 [get_ports {led[6]}]
# set_property PACKAGE_PIN B17 [get_ports {led[7]}]
# set_property IOSTANDARD LVCMOS15 [get_ports {led[*]}]

############################################################################
## System Clock
############################################################################
set_property IOSTANDARD LVDS_25 [get_ports {sysClkp}]
set_property PACKAGE_PIN W11 [get_ports {sysClkp}]

set_property IOSTANDARD LVDS_25 [get_ports {sysClkn}]
set_property PACKAGE_PIN W12 [get_ports {sysClkn}]

set_property DIFF_TERM FALSE [get_ports {sysClkp}]

create_clock -name sys_clk -period 5 [get_ports {sysClkp}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk clk_pll_i}] -group [get_clocks {okUH0 mmcm0_clk0}]

############################################################################
## Custom Pins
############################################################################
# J2-2  (bank 34) channel 1 Manchester input
set_property PACKAGE_PIN Y6 [get_ports {manchester}]
set_property IOSTANDARD LVCMOS33 [get_ports {manchester}]
# J2-4  (bank 34, same bank/VCCO as J2-2) channel 2 Manchester input (was dbg_sig1)
set_property PACKAGE_PIN AA6 [get_ports {manchester2}]
set_property IOSTANDARD LVCMOS33 [get_ports {manchester2}]
# J3-10
set_property PACKAGE_PIN F4 [get_ports {dbg_sig0}]
set_property IOSTANDARD LVCMOS33 [get_ports {dbg_sig0}]
# J2-18
set_property PACKAGE_PIN Y1 [get_ports {dbg_sig2}]
set_property IOSTANDARD LVCMOS33 [get_ports {dbg_sig2}]
# J2-26
set_property PACKAGE_PIN AA14 [get_ports {dbg_sig3}]
set_property IOSTANDARD LVCMOS33 [get_ports {dbg_sig3}]

############################################################################
## Recovered Manchester clocks
############################################################################
# Both decoders generate their output clock combinationally inside mandec
#   assign o_clk = ~i_reset | (read_clk ^ read_switch);
# so Vivado cannot infer it from a port or an MMCM. Without a create_clock the
# decoders and the FIFO write sides are never timed at all: before these
# constraints the routed design reported 645 TIMING-17 "non-clocked sequential
# cell" critical warnings, and "all user specified timing constraints are met"
# was a statement about the USB and system clocks only -- it said nothing
# whatsoever about either channel.
#
# These are NOT here to add buffering. Vivado already promotes both nets to a
# global buffer by itself, during implementation: the routed clock utilization
# report shows dec/wr_clk_BUFG_inst and dec2/wr_clk_BUFG_inst on BUFGCTRL_X0Y3
# and X0Y2. Those BUFG cells do not exist in the synthesized netlist, so do not
# try to constrain their pins -- the clock has to be defined at its source, the
# mandec output, and Vivado propagates it through the buffer it inserts later.
#
# dec/o_clk and dec2/o_clk survive as named pins because the corresponding nets
# carry (* mark_debug = "true" *) in USBInterface.v. Removing those attributes
# would let synthesis rename or absorb the nets and these constraints would stop
# matching, so keep them.
#
# Keep this block to plain create_clock / set_clock_groups calls. The XDC parser
# rejects Tcl control flow -- an earlier version used a foreach loop and Vivado
# skipped the whole thing with "Command 'foreach' is not supported in the xdc
# constraint file", leaving both clocks silently unconstrained.
#
# The bit period is Depth * 10 ns (Depth 12 -> 120 ns -> 8.33 MHz). 70 ns here is
# a fixed default so that a build driven from the GUI still gets both clocks
# timed; it is conservative for every Depth >= 7.
#
# It is NOT safe above 14.3 MHz, where it would be looser than the real period
# and timing would pass without checking anything. build_bitfile.tcl therefore
# generates hdl/build/recovered_clock_rate.xdc with the exact period for the
# Depth being built and marks it PROCESSING_ORDER LATE so it replaces these two
# lines. Build through that script for anything faster than Depth 7.
#
# KNOWN GAP: this constrains o_clk (the bit clock) but not o_recclk (the chip
# clock recovered by the ring oscillator, = o_clk * 2), which still leaves ten
# flops per channel untimed -- read_clk, read_switch and the three in buf2.
# Constraining o_recclk as well was tried on 2026-09-16 and reverted. It works,
# but it exposes four endpoints on a genuinely unanalysed crossing:
#   dec/dly_data/...srl_sig_reg[8] (clk_out1_clk_wiz_0, 400 MHz) -> buf2 (o_recclk)
# which fails by -3.75 ns. clk_out1_clk_wiz_0 is not named in any clock group
# below, and because o_clk is a LUT output Vivado propagates both clock edges
# ("TIMING 38-172 LUT was found on clock network") and analyses it very
# pessimistically. Closing that properly needs set_clock_sense plus probably a
# multicycle path, and is timing-closure work in its own right -- do it
# deliberately, not as a side effect of debugging a channel.
create_clock -name dec_clk  -period 70.000 [get_pins dec/o_clk]
create_clock -name dec2_clk -period 70.000 [get_pins dec2/o_clk]

# The two recovered clocks are asynchronous to each other and to everything
# else: each is regenerated from its own transmitter with no shared reference.
set_clock_groups -asynchronous -group [get_clocks dec_clk] -group [get_clocks dec2_clk] -group [get_clocks {sys_clk clk_pll_i}] -group [get_clocks {okUH0 mmcm0_clk0}]

############################################################################
## DDR3
############################################################################
set_property PACKAGE_PIN N18 [get_ports {ddr3_dq[0]}]
set_property PACKAGE_PIN L20 [get_ports {ddr3_dq[1]}]
set_property PACKAGE_PIN N20 [get_ports {ddr3_dq[2]}]
set_property PACKAGE_PIN K18 [get_ports {ddr3_dq[3]}]
set_property PACKAGE_PIN M18 [get_ports {ddr3_dq[4]}]
set_property PACKAGE_PIN K19 [get_ports {ddr3_dq[5]}]
set_property PACKAGE_PIN N19 [get_ports {ddr3_dq[6]}]
set_property PACKAGE_PIN L18 [get_ports {ddr3_dq[7]}]
set_property PACKAGE_PIN L16 [get_ports {ddr3_dq[8]}]
set_property PACKAGE_PIN L14 [get_ports {ddr3_dq[9]}]
set_property PACKAGE_PIN K14 [get_ports {ddr3_dq[10]}]
set_property PACKAGE_PIN M15 [get_ports {ddr3_dq[11]}]
set_property PACKAGE_PIN K16 [get_ports {ddr3_dq[12]}]
set_property PACKAGE_PIN M13 [get_ports {ddr3_dq[13]}]
set_property PACKAGE_PIN K13 [get_ports {ddr3_dq[14]}]
set_property PACKAGE_PIN L13 [get_ports {ddr3_dq[15]}]
set_property PACKAGE_PIN D22 [get_ports {ddr3_dq[16]}]
set_property PACKAGE_PIN C20 [get_ports {ddr3_dq[17]}]
set_property PACKAGE_PIN E21 [get_ports {ddr3_dq[18]}]
set_property PACKAGE_PIN D21 [get_ports {ddr3_dq[19]}]
set_property PACKAGE_PIN G21 [get_ports {ddr3_dq[20]}]
set_property PACKAGE_PIN C22 [get_ports {ddr3_dq[21]}]
set_property PACKAGE_PIN E22 [get_ports {ddr3_dq[22]}]
set_property PACKAGE_PIN B22 [get_ports {ddr3_dq[23]}]
set_property PACKAGE_PIN A20 [get_ports {ddr3_dq[24]}]
set_property PACKAGE_PIN D19 [get_ports {ddr3_dq[25]}]
set_property PACKAGE_PIN A19 [get_ports {ddr3_dq[26]}]
set_property PACKAGE_PIN F19 [get_ports {ddr3_dq[27]}]
set_property PACKAGE_PIN C18 [get_ports {ddr3_dq[28]}]
set_property PACKAGE_PIN E19 [get_ports {ddr3_dq[29]}]
set_property PACKAGE_PIN A18 [get_ports {ddr3_dq[30]}]
set_property PACKAGE_PIN C19 [get_ports {ddr3_dq[31]}]
set_property SLEW FAST [get_ports {ddr3_dq[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_dq[*]}]

set_property PACKAGE_PIN J21 [get_ports {ddr3_addr[0]}]
set_property PACKAGE_PIN J22 [get_ports {ddr3_addr[1]}]
set_property PACKAGE_PIN K21 [get_ports {ddr3_addr[2]}]
set_property PACKAGE_PIN H22 [get_ports {ddr3_addr[3]}]
set_property PACKAGE_PIN G13 [get_ports {ddr3_addr[4]}]
set_property PACKAGE_PIN G17 [get_ports {ddr3_addr[5]}]
set_property PACKAGE_PIN H15 [get_ports {ddr3_addr[6]}]
set_property PACKAGE_PIN G16 [get_ports {ddr3_addr[7]}]
set_property PACKAGE_PIN G20 [get_ports {ddr3_addr[8]}]
set_property PACKAGE_PIN M21 [get_ports {ddr3_addr[9]}]
set_property PACKAGE_PIN J15 [get_ports {ddr3_addr[10]}]
set_property PACKAGE_PIN G15 [get_ports {ddr3_addr[11]}]
set_property PACKAGE_PIN H13 [get_ports {ddr3_addr[12]}]
set_property PACKAGE_PIN K22 [get_ports {ddr3_addr[13]}]
set_property PACKAGE_PIN L21 [get_ports {ddr3_addr[14]}]
set_property SLEW FAST [get_ports {ddr3_addr[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_addr[*]}]

set_property PACKAGE_PIN H18 [get_ports {ddr3_ba[0]}]
set_property PACKAGE_PIN J19 [get_ports {ddr3_ba[1]}]
set_property PACKAGE_PIN H19 [get_ports {ddr3_ba[2]}]
set_property SLEW FAST [get_ports {ddr3_ba[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_ba[*]}]

set_property PACKAGE_PIN J16 [get_ports {ddr3_ras_n}]
set_property SLEW FAST [get_ports {ddr3_ras_n}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_ras_n}]

set_property PACKAGE_PIN H17 [get_ports {ddr3_cas_n}]
set_property SLEW FAST [get_ports {ddr3_cas_n}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_cas_n}]

set_property PACKAGE_PIN J20 [get_ports {ddr3_we_n}]
set_property SLEW FAST [get_ports {ddr3_we_n}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_we_n}]

set_property PACKAGE_PIN F21 [get_ports {ddr3_reset_n}]
set_property SLEW FAST [get_ports {ddr3_reset_n}]
set_property IOSTANDARD LVCMOS15 [get_ports {ddr3_reset_n}]

set_property PACKAGE_PIN G18 [get_ports {ddr3_cke[0]}]
set_property SLEW FAST [get_ports {ddr3_cke[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_cke[*]}]

set_property PACKAGE_PIN H20 [get_ports {ddr3_odt[0]}]
set_property SLEW FAST [get_ports {ddr3_odt[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_odt[*]}]

set_property PACKAGE_PIN L19 [get_ports {ddr3_dm[0]}]
set_property PACKAGE_PIN L15 [get_ports {ddr3_dm[1]}]
set_property PACKAGE_PIN D20 [get_ports {ddr3_dm[2]}]
set_property PACKAGE_PIN B20 [get_ports {ddr3_dm[3]}]
set_property SLEW FAST [get_ports {ddr3_dm[*]}]
set_property IOSTANDARD SSTL15 [get_ports {ddr3_dm[*]}]

set_property PACKAGE_PIN N22 [get_ports {ddr3_dqs_p[0]}]
set_property PACKAGE_PIN M22 [get_ports {ddr3_dqs_n[0]}]
set_property PACKAGE_PIN K17 [get_ports {ddr3_dqs_p[1]}]
set_property PACKAGE_PIN J17 [get_ports {ddr3_dqs_n[1]}]
set_property PACKAGE_PIN B21 [get_ports {ddr3_dqs_p[2]}]
set_property PACKAGE_PIN A21 [get_ports {ddr3_dqs_n[2]}]
set_property PACKAGE_PIN F18 [get_ports {ddr3_dqs_p[3]}]
set_property PACKAGE_PIN E18 [get_ports {ddr3_dqs_n[3]}]
set_property SLEW FAST [get_ports {ddr3_dqs*}]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {ddr3_dqs*}]

set_property PACKAGE_PIN J14 [get_ports {ddr3_ck_p[0]}]
set_property PACKAGE_PIN H14 [get_ports {ddr3_ck_n[0]}]
set_property SLEW FAST [get_ports {ddr3_ck*}]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {ddr3_ck_*}]
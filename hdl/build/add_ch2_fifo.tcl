# add_ch2_fifo.tcl -- create the channel-2 output FIFO for the two-channel build.
#
# Usage, from the Vivado Tcl Console with wireless_daq.xpr open:
#     source [get_property DIRECTORY [current_project]]/add_ch2_fifo.tcl
#
# Creates the IP core `fifo_w32_65536_r32_65536`, instantiated as `fifo2_out`
# in USBInterface.v. This is channel 2's buffer between the decimator chain
# (dec2_clk) and the OpalKelly block pipe 0xA1 (okClk). Only needs to be run
# once per clone; after that the .xci lives in the project.
#
# Channel 1 buffers into DDR3; channel 2 has no DDR3 backing, so this core is
# the whole buffer: 65536 x 32 bit = 256 KB of block RAM (~60 of the A75T's
# 105 BRAM tiles), about 250 ms at 8.33 Mbit/s. It was 32768 (128 KB, ~125 ms)
# until 2026-09-21; see "Changing the depth" at the end for why and how.
#
# The parameters mirror `fifo_ddr3_out` (the channel-1 pipe-out FIFO) so both
# channels present identical behaviour to the host: independent clocks, block
# RAM, standard (non-FWFT) reads, async reset, and a prog_empty threshold of
# 16 driving ep_ready.

set FIFO_NAME "fifo_w32_65536_r32_65536"
set BUF_DEPTH 65536

# prog_full backpressures the writer, mirroring channel 1's ~98% of depth.
set FULL_ASSERT [expr {$BUF_DEPTH - 68}]
set FULL_NEGATE [expr {$FULL_ASSERT - 1}]

# prog_empty drives pipe2_ready; 16/17 matches fifo_ddr3_out exactly.
set EMPTY_ASSERT 16
set EMPTY_NEGATE 17

if {[llength [current_project -quiet]] == 0} {
    error "No project open. Open hdl/build/wireless_daq.xpr first."
}

if {[llength [get_ips -quiet $FIFO_NAME]] > 0} {
    puts "IP $FIFO_NAME already exists -- nothing to do."
    puts "To rebuild it, first run: delete_ip \[get_ips $FIFO_NAME\]"
    return
}

puts "Creating IP $FIFO_NAME (depth $BUF_DEPTH x 32 bit)..."

create_ip -name fifo_generator -vendor xilinx.com -library ip \
    -module_name $FIFO_NAME

set_property -dict [list \
    CONFIG.Fifo_Implementation           {Independent_Clocks_Block_RAM} \
    CONFIG.Performance_Options           {Standard_FIFO} \
    CONFIG.INTERFACE_TYPE                {Native} \
    CONFIG.Input_Data_Width              {32} \
    CONFIG.Input_Depth                   $BUF_DEPTH \
    CONFIG.Output_Data_Width             {32} \
    CONFIG.Output_Depth                  $BUF_DEPTH \
    CONFIG.Reset_Type                    {Asynchronous_Reset} \
    CONFIG.Enable_Reset_Synchronization  {true} \
    CONFIG.Enable_Safety_Circuit         {true} \
    CONFIG.Full_Flags_Reset_Value        {1} \
    CONFIG.Programmable_Full_Type        {Single_Programmable_Full_Threshold_Constant} \
    CONFIG.Full_Threshold_Assert_Value   $FULL_ASSERT \
    CONFIG.Full_Threshold_Negate_Value   $FULL_NEGATE \
    CONFIG.Programmable_Empty_Type       {Single_Programmable_Empty_Threshold_Constant} \
    CONFIG.Empty_Threshold_Assert_Value  $EMPTY_ASSERT \
    CONFIG.Empty_Threshold_Negate_Value  $EMPTY_NEGATE \
    CONFIG.Almost_Full_Flag              {false} \
    CONFIG.Almost_Empty_Flag             {false} \
    CONFIG.Valid_Flag                    {false} \
    CONFIG.Overflow_Flag                 {false} \
    CONFIG.Underflow_Flag                {false} \
    CONFIG.Write_Acknowledge_Flag        {false} \
    CONFIG.Data_Count                    {false} \
    CONFIG.Write_Data_Count              {false} \
    CONFIG.Read_Data_Count               {false} \
    CONFIG.Use_Embedded_Registers        {false} \
    CONFIG.use_dout_register             {false} \
] [get_ips $FIFO_NAME]

set xci [get_property IP_FILE [get_ips $FIFO_NAME]]
generate_target all [get_files $xci]
create_ip_run [get_files $xci]

puts "Created IP $FIFO_NAME"
puts "Ports: rst wr_clk rd_clk din\[31:0\] wr_en rd_en dout\[31:0\] full empty \
prog_full prog_empty wr_rst_busy rd_rst_busy"
puts "prog_full asserts at $FULL_ASSERT / $BUF_DEPTH, prog_empty at $EMPTY_ASSERT."
puts "Now run Generate Bitstream."

# Changing the depth
# ------------------
# The depth appears in three places and they must agree: FIFO_NAME and
# BUF_DEPTH above, and the instantiation at USBInterface.v ~line 400. A core
# whose name understates its size is the provenance trap that has already cost
# this project a bench session, so rename rather than quietly widen.
#
# To change it:
#   1. delete_ip [get_ips fifo_w32_65536_r32_65536]
#   2. edit FIFO_NAME and BUF_DEPTH here, and the instantiation in USBInterface.v
#   3. re-source this script, then rebuild
#
# Depth vs. block RAM on the A75T (105 tiles), and the host stall it rides out
# at 8.33 Mbit/s:
#
#   32768 x 32 bit = 128 KB = ~30 tiles = ~125 ms   (before 2026-09-21)
#   65536 x 32 bit = 256 KB = ~60 tiles = ~250 ms   (current)
#
# 65536 is close to the practical ceiling: DDR3 and the channel-1 chain want
# the rest. Check Report Utilization and timing after any change.

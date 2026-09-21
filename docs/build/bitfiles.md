# The bitfiles

Every file here is a **two-channel** build: both J2-2 and J2-4 active, IEEE
convention, 3.3 V. All were built by `build_bitfile.tcl`, all met timing, and
all include the [FIFO reset sequencer](../design/reset-sequencer.md).

Each `.bit` has a `.txt` beside it recording exactly how it was built.

## `hdl/build/` — use these

Debug pins carry `dec_clk`, `dec2_clk`, `pipe2_ready`.

!!! warning "Mixed channel-2 buffers — the 8.33 MHz file is the odd one out"
    Channel 2's buffer changed twice on 2026-09-21: 128 KB block RAM → 256 KB
    block RAM → a 256 MiB DDR3 ring. Only the 8.33 MHz file has been rebuilt
    for the DDR3 version; the other eight still carry the original 128 KB
    block-RAM buffer and are several commits behind the source tree. The
    **ch2 buf** column below says which is which. Rebuild the rest with
    `build_bitfile.tcl` if you need them to match.

| Bitfile | Depth | Rate | ch2 buf | WNS | Hardware-confirmed |
|---|---|---|---|---|---|
| `USBInterface-10mhz-J2_2+J2_4-3v3-IEEE.bit` | 10 | 10 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-12_5mhz-J2_2+J2_4-3v3-IEEE.bit` | 8 | 12.5 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-14_29mhz-J2_2+J2_4-3v3-IEEE.bit` | 7 | 14.29 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-16_67mhz-J2_2+J2_4-3v3-IEEE.bit` | 6 | 16.67 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-20mhz-J2_2+J2_4-3v3-IEEE.bit` | 5 | 20 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-25mhz-J2_2+J2_4-3v3-IEEE.bit` | 4 | 25 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-33_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 3 | 33.33 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-50mhz-J2_2+J2_4-3v3-IEEE.bit` | 2 | 50 MHz | 128 KB BRAM | 0.208229 ns | — |
| `USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 12 | 8.33 MHz | 256 MiB DDR3 | 0.208229 ns | decoder yes; **DDR3 buffer not yet** |

**8.33 MHz is the one to use** — it matches the transmitters in current service
and is the only rate confirmed decoding on hardware. That confirmation predates
the DDR3 buffer: the decoder, pinout and reset sequencing are unchanged, but
the loss rate this build was made to improve has not been re-measured. Built
2026-09-21 from a clean tree, WNS 0.208229 ns, WHS 0.024302 ns, `dec_clk` and
`dec2_clk` timed at 120.000 ns, **20 of 105 block-RAM tiles** — down from 70,
because deleting the 256 KB channel-2 FIFO freed 50 tiles that the two small
DDR3 FIFOs replacing it do not need.

!!! note "Built at `c4154f3`, not at branch HEAD"
    Later commits on `ch2-ddr3` are simulation-only — the MIG behavioural
    model, the testbench wiring, and docs. The one design-file change among
    them is an `ifdef` that selects the model, and it resolves to the real
    `xem7310_a75_mig` whenever `SIM_MIG_MODEL` is not defined, which is
    everywhere except the simulation fileset. The synthesised netlist is
    unchanged, so the bitfile has not been rebuilt for them.

!!! note "Timing did not move"
    WNS is 0.208229 ns, the same value every build of this design has had at
    every rate. Arbitrating the memory controller between two channels cost
    nothing, which is consistent with the critical path being the DDR3/USB
    interface rather than anything the arbiter touches.

## `hdl/build/ch1_debug/`

Identical builds with the channel-1-era debug signals (`data_dly`,
`init_calib_complete`, `dec_data_bit`) on the spare pins instead. Only needed
when debugging channel 1's decoder itself.

## What "meets timing" does and does not mean

Every rate above closes timing with the same WNS, because the critical path is
the DDR3/USB interface rather than the decoder. Simulation likewise shows every
rate decoding at error rate 0.0 at its nominal rate, up to 50 MHz.

Neither gives you a ceiling. What narrows with rate is **tolerance to an
off-nominal transmitter**, and behavioural simulation has no jitter, no analog
edge degradation and no Y6/AA6 crosstalk — all of which eat that same margin.
See [Measurements](../reference/measurements.md#rate-tolerance).

!!! danger "Rates above 8.33 MHz are untested on hardware"
    Treat them as candidates, not as working builds.

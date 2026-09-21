# The bitfiles

Every file here is a **two-channel** build: both J2-2 and J2-4 active, IEEE
convention, 3.3 V. All were built by `build_bitfile.tcl`, all met timing, and
all include the [FIFO reset sequencer](../design/reset-sequencer.md).

Each `.bit` has a `.txt` beside it recording exactly how it was built.

## `hdl/build/` — use these

Debug pins carry `dec_clk`, `dec2_clk`, `pipe2_ready`.

!!! warning "Mixed channel-2 buffer sizes"
    `fifo2_out` was doubled from 128 KB to 256 KB on 2026-09-21. Only the
    8.33 MHz file has been rebuilt with it; the other eight still carry the
    128 KB buffer and are one commit behind the source tree. The **ch2 buf**
    column below says which is which. Rebuild the rest with
    `build_bitfile.tcl` if you need them to match.

| Bitfile | Depth | Rate | ch2 buf | WNS | Hardware-confirmed |
|---|---|---|---|---|---|
| `USBInterface-10mhz-J2_2+J2_4-3v3-IEEE.bit` | 10 | 10 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-12_5mhz-J2_2+J2_4-3v3-IEEE.bit` | 8 | 12.5 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-14_29mhz-J2_2+J2_4-3v3-IEEE.bit` | 7 | 14.29 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-16_67mhz-J2_2+J2_4-3v3-IEEE.bit` | 6 | 16.67 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-20mhz-J2_2+J2_4-3v3-IEEE.bit` | 5 | 20 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-25mhz-J2_2+J2_4-3v3-IEEE.bit` | 4 | 25 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-33_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 3 | 33.33 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-50mhz-J2_2+J2_4-3v3-IEEE.bit` | 2 | 50 MHz | 128 KB | 0.208229 ns | — |
| `USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 12 | 8.33 MHz | 256 KB | 0.208229 ns | decoder yes; **256 KB buffer not yet** |

**8.33 MHz is the one to use** — it matches the transmitters in current service
and is the only rate confirmed decoding on hardware. That confirmation predates
the 256 KB buffer: the decoder, pinout and reset sequencing are unchanged, but
the loss rate this build was made to improve has not been re-measured. Built
2026-09-21 from a clean tree, WNS 0.208229 ns, WHS 0.025308 ns, `dec_clk` and
`dec2_clk` timed at 120.000 ns, 70 of 105 block-RAM tiles.

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

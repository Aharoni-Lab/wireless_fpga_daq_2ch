# Pinout

!!! warning "Two different numbering schemes"
    The `J2-x` / `J3-x` labels are the **breakout board's** own numbering and do
    **not** match the Opal Kelly module pinout. Opal Kelly calls the two
    Manchester inputs `MC1-42` (Y6) and `MC1-44` (AA6). Always confirm against
    the FPGA pin name, which is what `xem7310.xdc` constrains.

## Data inputs

| Breakout | FPGA pin | Bank | Signal |
|---|---|---|---|
| J2-2 | `Y6` | 34 | `manchester` — channel 1 |
| J2-4 | `AA6` | 34 | `manchester2` — channel 2 |

Both `LVCMOS33`, single-ended, 3.3 V.

`Y6` and `AA6` are `B34_L18P` and `B34_L18N` — two halves of one differential
pair. Legal as independent single-ended inputs; the tightest-coupled pair on the
connector, so the first suspect for channel interference at high rates.

## Debug outputs

Three spare output pins. Which signals they carry is set by `DEBUG_MODE` in
`USBInterface.v`.

=== "DEBUG_MODE = 1 (default, `hdl/build/`)"

    | Breakout | FPGA pin | Signal | How to read it |
    |---|---|---|---|
    | J3-10 | `F4` | `dec_clk` | channel 1 recovered clock. Ticking = decoder locked. Dead = never locked at this rate, whatever the host reports |
    | J2-18 | `Y1` | `dec2_clk` | the same for channel 2 |
    | J2-26 | `AA14` | `pipe2_ready` | `ep_ready` for pipe 0xA1. Low forever while `dec2_clk` is healthy = the channel-2 buffer or its reset is at fault, not the decoder |

=== "DEBUG_MODE = 0 (`hdl/build/ch1_debug/`)"

    | Breakout | FPGA pin | Signal |
    |---|---|---|
    | J3-10 | `F4` | `data_dly` |
    | J2-18 | `Y1` | `init_calib_complete` |
    | J2-26 | `AA14` | `dec_data_bit` |

    The channel-1-era set. Note none of these is a recovered clock, which is the
    single most useful signal when trying an unfamiliar rate.

!!! danger "`dbg_sig1` does not exist on this design"
    That pin (`AA6`) is now `manchester2`, an **input**. Loading a
    single-channel bitfile while a transmitter is wired to J2-4 puts two drivers
    on one net — on the FPGA and on the transmitter.

## WireIn 0x00

| Bit | Signal | Note |
|---|---|---|
| 0 | `clk_reset` | active high |
| 1 | `fifo_reset` | active high |
| 2 | `dec_reset` | **inverted** in RTL: `dec_reset = ~ep00wire[2]` |
| 3 | `ddr3_reset` | active high |

The host reset sequence used by miniscope-io is `0b0010`, `0b0`, `0b1000`,
`0b0` — pulse `fifo_reset`, then `ddr3_reset`.

Since the [reset sequencer](../design/reset-sequencer.md), `fifo_reset` no
longer reaches the recovered-clock FIFOs directly; it arms the per-channel
sequencers instead.

## Clocks

| Clock | Source | Period | Free-running? |
|---|---|---|---|
| `sysClkp`/`sysClkn` | 200 MHz oscillator | 5 ns | yes |
| `genClk` | ×2 from `sys_clk` | 2.5 ns | yes |
| `okClk` | Opal Kelly USB | 9.92 ns | yes |
| `ui_clk` | DDR3 MIG | — | yes |
| `dec_clk` | recovered, channel 1 | 120 ns @ 8.33 MHz | **no — stops when idle** |
| `dec2_clk` | recovered, channel 2 | 120 ns @ 8.33 MHz | **no — stops when idle** |

Both recovered clocks are constrained in `xem7310.xdc` and Vivado promotes both
to global buffers on its own.

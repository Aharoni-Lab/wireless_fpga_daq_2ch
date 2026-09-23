# The bitfiles

Every file here is a **two-channel** build: both J2-2 and J2-4 active, IEEE
convention, 3.3 V. All were built by `build_bitfile.tcl`, all met timing, and
all include the [FIFO reset sequencer](../design/reset-sequencer.md).

Each `.bit` has a `.txt` beside it recording exactly how it was built.

## Reading a bitfile name

```
USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit
```

| Part | In this name | Meaning |
|---|---|---|
| top module | `USBInterface` | always the same |
| data rate | `8_33mhz` | 8.33 Mbit/s per channel, `_` for the decimal point. **Must match the transmitter** |
| input pins | `J2_2+J2_4` | breakout pins carrying data: J2-2 is channel 1, J2-4 is channel 2. Single-channel builds say `J2_2` only |
| IO voltage | `3v3` | 3.3 V input level |
| convention | `IEEE` | Manchester convention — see [Manchester decoder](../design/decoder.md#manchester-convention) |

miniscope-io parses the name, so never rename a bitfile.

## Which one to use

**`USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit`.** It is the only file built from
the current source — both channels buffered in DDR3 — and the only one working
on hardware. It matches the transmitters in current service.

!!! warning "The other rates are out of date"
    The other eight files in `hdl/build/`, and everything in
    `hdl/build/ch1_debug/`, are 2026-09-17 builds from before this
    repository's history starts: channel 2 still has the old 128 KB block-RAM
    buffer, and their stamps point at commits that are not in this repository.
    Rebuild one before using it — see [Using a different rate](#using-a-different-rate).

| Bitfile | Depth | Rate | ch2 buffer | Hardware |
|---|---|---|---|---|
| `USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 12 | 8.33 MHz | 256 MiB DDR3 | **working** |
| `USBInterface-10mhz-J2_2+J2_4-3v3-IEEE.bit` | 10 | 10 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-12_5mhz-J2_2+J2_4-3v3-IEEE.bit` | 8 | 12.5 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-14_29mhz-J2_2+J2_4-3v3-IEEE.bit` | 7 | 14.29 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-16_67mhz-J2_2+J2_4-3v3-IEEE.bit` | 6 | 16.67 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-20mhz-J2_2+J2_4-3v3-IEEE.bit` | 5 | 20 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-25mhz-J2_2+J2_4-3v3-IEEE.bit` | 4 | 25 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-33_33mhz-J2_2+J2_4-3v3-IEEE.bit` | 3 | 33.33 MHz | 128 KB BRAM, stale | not run |
| `USBInterface-50mhz-J2_2+J2_4-3v3-IEEE.bit` | 2 | 50 MHz | 128 KB BRAM, stale | not run |

The 8.33 MHz file: built 2026-09-21 from a clean tree at `a0e5c13`, WNS
0.208229 ns, WHS 0.024302 ns, `dec_clk` and `dec2_clk` timed at 120.000 ns,
20 of 105 block-RAM tiles.

## Using a different rate

The rate is fixed at build time and must match the transmitter. See
[Changing the rate](../design/decoder.md#changing-the-rate) for which rates
exist.

1. **Build it** from the current source, giving the shift depth
   (`rate = 100 / Depth` MHz):
   ```bash
   vivado -mode batch -source hdl/build/build_bitfile.tcl -tclargs 10
   ```
   This replaces the stale file of the same name and its `.txt`; commit both.
   See [Building a bitfile](building.md).
2. **Copy** the `.bit` into `mio/devices/XEM7310-A75/` in your miniscope-io
   checkout, name unchanged.
3. **Point your stream config at it** with `bitstream:` — see
   [Host side](../host/capture.md#selecting-a-channel).
4. **Treat it as untested** until it has run on the bench. Only 8.33 MHz has.

## `hdl/build/ch1_debug/`

The same rates with channel-1 debug signals (`data_dly`, `init_calib_complete`,
`dec_data_bit`) on the spare pins instead of the recovered clocks — see
[Pinout](../reference/pinout.md#debug-outputs). Only needed when debugging
channel 1's decoder itself. All of them are stale; to rebuild one, set
`DEBUG_MODE = 0` in `USBInterface.v` before running the build.

## What "meets timing" does and does not mean

Every rate closes timing with the same WNS, because the critical path is the
DDR3/USB interface rather than the decoder. Simulation likewise shows every
rate decoding at error rate 0.0 at its nominal rate, up to 50 MHz.

Neither gives you a ceiling. What narrows with rate is **tolerance to an
off-nominal transmitter**, and behavioural simulation has no jitter, no analog
edge degradation and no Y6/AA6 crosstalk — all of which eat that same margin.

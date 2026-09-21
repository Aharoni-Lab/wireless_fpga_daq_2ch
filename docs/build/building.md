# Building a bitfile

Use `build_bitfile.tcl`. It sets the rate, forces the IP to regenerate, refuses
to hand you a bitfile that failed timing, copies the result out under its scheme
name, and writes a provenance stamp beside it.

```bash
vivado -mode batch -source hdl/build/build_bitfile.tcl -tclargs 12
```

The argument is the **shift depth**, not the rate. `rate = 100 / Depth` MHz:

| Depth | Rate | | Depth | Rate |
|---|---|---|---|---|
| 12 | 8.33 MHz | | 5 | 20 MHz |
| 10 | 10 MHz | | 4 | 25 MHz |
| 8 | 12.5 MHz | | 3 | 33.33 MHz |
| 7 | 14.29 MHz | | 2 | 50 MHz |
| 6 | 16.67 MHz | | | |

The rate applies to **both channels**.

## Why not do it by hand

Until `build_bitfile.tcl` existed, nothing forced `c_shift_ram_0` to regenerate
when its `Depth` changed. A build could be labelled one rate and synthesised at
another, and several early bitfiles could not be reproduced from any committed
tree. The script removes that whole class of mistake — prefer it over clicking
through *Re-customize IP*.

## The provenance stamp

Every build writes a `.txt` next to the bitfile:

```
bitfile:      USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit
built:        2026-09-17 13:20:49
vivado:       2023.2
git commit:   081c9e919d7e0411e1549065bbee491b678bd321
git dirty:    yes
shift depth:  12  (=> 8.33 MHz on both channels)
WNS:          0.208229 ns
WHS:          0.021344 ns
clock:        dec_clk period 120.000 ns
clock:        dec2_clk period 120.000 ns
```

Commit the `.txt` with the `.bit`. `git dirty: yes` means the tree had
uncommitted changes — treat that build as unreproducible.

!!! warning "Timing is not the limit"
    WNS is 0.208 ns for **every** rate from 8.33 to 50 MHz, because the critical
    path is the DDR3/USB interface, not the decoder. A bitfile closing timing
    tells you nothing about whether it can recover Manchester at that rate. See
    [Measurements](../reference/measurements.md).

## Naming

[miniscope-io](https://github.com/miniscope/mio) parses the filename, so the scheme is not decorative:

```
USBInterface-<rate>-<input pins>-<IO voltage>-<Manchester convention>.bit
```

e.g. `USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit`. No spaces, no extra periods;
miniscope-io's test suite checks this.

!!! note
    `wireless_daq.runs/impl_1/USBInterface.bit` is overwritten by every build.
    Always copy the result out under its scheme name — `build_bitfile.tcl` does
    this for you.

## Debug pin variants

`DEBUG_MODE` in `USBInterface.v` selects which signals reach the three spare
output pins. The `hdl/build/` bitfiles use the default (`1`, both recovered
clocks plus `pipe2_ready`); `hdl/build/ch1_debug/` holds the same rates built
with the channel-1-era signal set. See [Pinout](../reference/pinout.md).

## Changing the channel-2 buffer

There is no channel-2 IP to generate any more. Both of its FIFOs are second
instances of cores channel 1 already uses, and the buffer itself is a DDR3
ring sized by `RING_ADDR_BITS` in `hdl/source/design/ddr3/ddr3_ui.v` — 26,
meaning 256 MiB per channel. Changing it is a one-line edit with no IP
regeneration.

Both rings must fit in the device together: the channel bit sits immediately
above `RING_ADDR_BITS`, so the two of them occupy `2^(RING_ADDR_BITS+1)`
words of `app_addr`. 26 puts that at 512 MiB on a 1 GiB board.

!!! tip "Check it in simulation first"
    `tb_ddr3_ui` overrides `RING_ADDR_BITS` to 5 so ring wrap and the
    full/empty conditions happen in microseconds. See
    [the arbiter testbench](../simulation/testbench.md#the-arbiter-testbench).

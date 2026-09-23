# Troubleshooting

## Pipe 0xA1 returns nothing / `Read failed: -1`

```
[mio.okDev] Read failed: -1
StreamReadError: Read failed: -1
```

`ep_ready` never rose, so the read timed out.

1. **Is the channel-2 transmitter actually running?** A channel is *held in
   reset until its transmitter appears* (see the
   [reset sequencer](../design/reset-sequencer.md)). With nothing on J2-4,
   `pipe2_ready` (J2-26) sits low and `0xA1` returns nothing. **This is correct
   behaviour.**
2. **Is `dec2_clk` (J2-18) ticking?** If dead, the decoder never locked — wrong
   rate, wrong convention, or no signal. If healthy while `pipe2_ready` stays
   low, the fault is the buffer or its reset, not the decoder.
3. **Is it a single-channel bitfile?** Then `AA6` is an *output* and you have
   driver contention. Load a `J2_2+J2_4` file.

## Data looks like corruption, preamble not found

Almost always the **Manchester convention**. `normal` and IEEE produce inverted
data from the same signal, and the wrong one does not look inverted — it looks
like garbage, because the preamble search fails. All bitfiles here are IEEE.

Second suspect: **wrong rate**. The bitfile's shift depth must match the
transmitter. Check the `.txt` stamp against what the transmitter is sending.

## `pixel_count` of 4776 instead of 5032

Normal. The last buffer of each frame is short: 7 × 5032 + 4776 = exactly
40000 px = 200 × 200. Expect it on 1 buffer in 8.

## Lost buffers on channel 2 during two-channel capture

Check the bitfile first. The stale builds still give channel 2 the old 128 KB
block-RAM buffer, which cannot ride out the host stalling on the other pipe; the
8.33 MHz bitfile buffers channel 2 in DDR3. See [The bitfiles](../build/bitfiles.md).

## Simulation hangs with no output

The watchdog should catch it:

```
TIMEOUT: no $finish after 8000000 ns.
  A pipe read is most likely still blocked waiting on ep_ready.
```

That is the signature of a FIFO reset that never completed — see
[The FIFO reset sequencer](../design/reset-sequencer.md). With `REAL_MIG=1` it
is expected: MIG calibration never converges in simulation, which is why the
default run uses a behavioural model — see
[Running the testbench](../simulation/testbench.md#the-memory-controller-is-a-model).

## Vivado cannot find `mig.prj`

See [Vivado setup](../build/vivado-setup.md). This repo ships the file at
`hdl/source/board/OpalKelly/XEM7310-A75/1.0/1.0/mig.prj`.

---

## Open items

### Simultaneous live display

Both channels can be captured at once but not *displayed* live at once.
`StreamDaq` assumes one device, one pipe, one display. Nothing in the hardware
prevents it.

### Other rates

Only 8.33 MHz is built from the current source and working on hardware. The
other rates need rebuilding and a bench run — see
[The bitfiles](../build/bitfiles.md).

### Two-channel support in miniscope-io

`pipe_addr`, the two-channel configs and `capture_both_channels.py` are not
merged into upstream miniscope-io yet — see [Host side](../host/capture.md).

---

## Provenance

Two rules, both learned expensively:

1. **Never ship a bitfile you cannot rebuild.** One built from an uncommitted
   edit misleads whoever flashes it next — as a control, it makes a working rig
   look broken.
2. **Keep IP names honest.** A core named `..._32768` that is actually 65536
   deep will mislead the next person.

`build_bitfile.tcl` enforces the first by writing a `.txt` stamp with the git
commit and a dirty flag. If a stamp says `git dirty: yes`, that build is not
reproducible.

!!! warning "Stamps built before 2026-09-21 all say `git dirty: yes`"
    Those builds sampled the flag after the build had already modified tracked
    files, so it always read `yes`. Read those stamps as "unknown", not as
    "dirty". Current stamps say `(sampled before the build wrote anything)`.

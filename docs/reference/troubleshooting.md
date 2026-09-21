# Troubleshooting

## Pipe 0xA1 returns nothing / `Read failed: -1`

```
[mio.okDev] Read failed: -1
StreamReadError: Read failed: -1
```

`ep_ready` never rose, so the read timed out.

1. **Is the channel-2 transmitter actually running?** Since the
   [reset sequencer](../design/reset-sequencer.md), a channel is *held in reset
   until its transmitter appears*. With nothing on J2-4, `pipe2_ready` (J2-26)
   sits low and `0xA1` returns nothing. **This is correct behaviour.**
2. **Is `dec2_clk` (J2-18) ticking?** If dead, the decoder never locked — wrong
   rate, wrong convention, or no signal. If healthy while `pipe2_ready` stays
   low, the fault is the buffer or its reset, not the decoder.
3. **Is this a pre-sequencer bitfile?** Before commit `bf9dbed`, resetting while
   channel 2 was idle wedged the FIFO permanently. Check the `.txt` stamp.
4. **Is it a single-channel bitfile?** Then `AA6` is an *output* and you have
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

Known, quantified: ~11 buffers per 30 s, isolated single-buffer gaps, channel 1
unaffected. See [Measurements](measurements.md#two-channel-capture) for what has
been ruled out. Host-side mitigations are exhausted; the proposal below is the
remaining lever.

## Simulation hangs with no output

The watchdog should catch it:

```
TIMEOUT: no $finish after 8000000 ns.
  A pipe read is most likely still blocked waiting on ep_ready.
```

That is the reset-ordering signature. Also note **DDR3 calibration does not
converge in simulation**, so channel 1 cannot be exercised there — use
`CH2_ONLY=1`.

## Vivado cannot find `mig.prj`

See [Vivado setup](../build/vivado-setup.md). This repo ships the file at
`hdl/source/board/OpalKelly/XEM7310-A75/1.0/1.0/mig.prj`.

---

## Open items

### Simultaneous live display

Both channels can be captured at once but not *displayed* live at once.
`StreamDaq` assumes one device, one pipe, one display. Nothing in the hardware
prevents it.

### Free-running write clock for `fifo2_out`

The reset sequencer makes reset order irrelevant, but `fifo2_out`'s write clock
is still a recovered clock. Crossing out of `dec2_clk` earlier — so the pipe-out
FIFO's write side free-runs like channel 1's — would remove the whole class of
problem. Not currently needed.

---

## Provenance

Two rules, both learned expensively:

1. **Never ship a bitfile you cannot rebuild.** Early single-channel "control"
   bitfiles were built from an uncommitted source edit. They produced 39%
   corrupt buffers, and anyone flashing one as a control would conclude the rig
   or the branch was broken. They are not in this repository.
2. **Keep IP names honest.** A core named `..._32768` that is actually 65536
   deep will mislead the next person.

`build_bitfile.tcl` enforces the first by writing a `.txt` stamp with the git
commit and a dirty flag. If a stamp says `git dirty: yes`, that build is not
reproducible.

!!! warning "Stamps built before 2026-09-21 all say `git dirty: yes`"
    The flag was sampled *after* the script had copied the `.bit` over a tracked
    file and Vivado had rewritten the `.xpr`, so git always had something to
    report and the answer was always `yes`. It never distinguished a clean build
    from a dirty one. It is now sampled before the build writes anything, and
    the stamp says so. Read the older stamps as "unknown", not as "dirty".

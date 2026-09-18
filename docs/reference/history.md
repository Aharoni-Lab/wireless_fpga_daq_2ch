# How channel 2 was fixed

Kept because the dead ends are informative: four plausible hypotheses were
wrong, and each was eliminated by measurement rather than argument. If channel 2
misbehaves again, start here before re-deriving any of it.

## The symptom

Channel 1 worked perfectly. Channel 2 returned nothing:
`ReadFromBlockPipeOut(0xA1)` failed with `-1` because `ep_ready` never asserted.
This persisted for years across several attempts.

## Wrong hypothesis 1 — wiring, ground, signal quality

Channel 2's input was brought to a clean, full-swing 3.3 V square wave,
confirmed on a scope. It still failed.

Sharing a ground pin between J2-2 and J2-4 is *not* a fault — all GND pins are
the same net. What matters is return-path loop area.

## Wrong hypothesis 2 — wrong pad

Proved empirically that J2-4 really is `AA6`: on the single-channel design
`dbg_sig1` is driven by `dec_clk`, and probing the J2-4 pad on the breakout
showed a clean recovered clock there.

Worth knowing: Opal Kelly numbers these `MC1-42` (Y6) and `MC1-44` (AA6). The
`J2-x` labels are the breakout's own and do not match the module pinout.

## Wrong hypothesis 3 — the RTL was asymmetric

Every structural element was checked against channel 1 and found correct: port
direction, pin constraint and IO standard, decoder parameters, shared resets,
FIFO clock domains, the `prog_empty` threshold, `pipe2_ready`, the endpoint
address, and the `okWireOR` width. All symmetric.

## Wrong hypothesis 4 — the recovered clock lacked a global buffer

This was the leading theory for some time, and it was **wrong**. The routed
design shows Vivado had already promoted both recovered clocks on its own:

| clock | global buffer | site | loads |
|---|---|---|---|
| `dec/wr_clk` (ch 1) | `dec/wr_clk_BUFG_inst/O` | `BUFGCTRL_X0Y3` | 275 |
| `dec2/wr_clk` (ch 2) | `dec2/wr_clk_BUFG_inst/O` | `BUFGCTRL_X0Y2` | 354 |

Channel 2 was never on general fabric; forcing `CLOCK_BUFFER_TYPE` would have
changed nothing.

What *was* true: neither recovered clock was **constrained**. Neither appeared
in the Clock Summary and the routed design carried 645 `TIMING-17` critical
warnings. "All user specified timing constraints are met" covered only the USB
and system clocks. Constraints for both are now in `xem7310.xdc` — worth adding,
but not the bug.

!!! warning "A clean timing report proved nothing here"
    Unconstrained paths are never analysed. Do not read WNS ≥ 0 as evidence that
    a decoder is correctly implemented.

## A false failure in the testbench

Two channel-2 simulations had been run and never interpreted. The most recent
scored a 30% error rate, which reads like a real logic bug. It was not — the
generator encoded the *normal* convention while the design was IEEE, so every
recovered bit came back complemented. It scored 30% rather than an obvious 100%
because the inverted preamble still contains the search pattern, shifted by four
bits, so the aligner locked onto garbage.

Once corrected, channel 2 decoded at **error rate 0.0** over the full payload —
clearing the decoder, the FIFO chain, the CDC, `prog_empty`/`ep_ready`, `epA1`
and `okWireOR` in one step.

## The actual cause — reset ordering

`mandec` stalls its recovered clock when it sees no valid symbols.
`fifo2_out` is the only pipe-out FIFO whose write clock is a recovered clock,
and it is an independent-clocks core with async reset and the safety circuit
enabled — it needs both clocks running to complete a reset.

Reset it while channel 2 is idle and it never accepts writes, and never
recovers. Removing only the testbench's channel-2 reset pulses took the pipe
from 1024 bytes to zero, still blocked a millisecond after valid data began
arriving.

Fixed by the [per-channel reset sequencers](../design/reset-sequencer.md).
Channel 1 carried the same latent fault via `fifo_ddr3_in`, and escaped only
because its transmitter was always already streaming at reset.

## Confirmation, 2026-09-18

| test | result |
|---|---|
| ch2 alone, transmitter started first | 3293 buffers, 0 dropped, 0.03% jumps |
| ch2 alone, **capture started first** | 1800 buffers, 0 dropped, **0.00% jumps** |
| both channels simultaneously, 30 s | 0 dropped on either |

The second row is the one that matters: the capture issued its reset into a
silent channel — the exact condition that used to block forever — and channel 2
came up on its own when the transmitter started.

## What it cost

Roughly: a bench session lost to a known-bad control bitfile that could not be
rebuilt from any committed tree, a second session on the BUFG theory, and an
unknown amount to an uninterpreted simulation that was reporting a false
failure. Hence the provenance rules in
[Troubleshooting](troubleshooting.md#provenance).

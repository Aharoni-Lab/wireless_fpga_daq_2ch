# Measurements

Everything here was measured. Where something is inferred or untested it says so.

## Two-channel capture

Two miniscopes, both transmitting, 8.33 Mbit/s each, 30 s, one XEM7310, one USB
cable. Captured 2026-09-18 with `capture_both_channels.py` reading both
endpoints from a single device handle.

| | ch1 (0xA0 / J2-2) | ch2 (0xA1 / J2-4) |
|---|---|---|
| buffers | 4845 | 4855 |
| frames | 606 | 609 |
| dropped buffers | **0** | **0** |
| lost buffers (gaps in `buffer_count`) | **0** | 11 |
| affected frames | 0 | ~11 of 609 (1.8%) |

**Channel 1 is clean. Channel 2 loses roughly one buffer every 2.7 s** under
simultaneous capture, appearing as isolated single-buffer gaps — one torn frame,
not a dropout.

### Single channel

Either channel read on its own is clean:

| run | lost buffers |
|---|---|
| ch2 alone, 4868 buffers | **0** |
| ch1 alone, 4824 buffers | **0** |

So the loss requires both pipes to be served from one handle.

### What the loss is, and is not

Ruled out by measurement:

| hypothesis | test | result |
|---|---|---|
| Crosstalk on the Y6/AA6 pair | swap the two transmitters | loss did not follow the pin |
| Host read rate too low | chunked reads, 1 → 8 → 64 buffers/call | rate identical at 824 kB/s; reads self-pace |
| Startup transient | discard first 8 s | no effect; losses spread uniformly through the run |
| One thread per pipe | threaded reader | **much worse** — ch1 lost 536 buffers; concurrent FrontPanel calls on one handle are not safe |

What does reproduce is a dependence on how long the host stays blocked on the
other pipe:

| ch1 blocked for | ch2 buffers lost / 30 s |
|---|---|
| ~6 ms (`--chunk 1`) | 20 |
| ~49 ms (`--chunk 8`) | 15 |
| **~390 ms (`--chunk 64`)** | **83** |

Channel 2 holds ~159 ms. Crossing that threshold multiplies the loss, which
confirms starvation above it. Below it the losses persist at a floor of ~12–20,
best explained by the **tail** of the stall distribution — occasional scheduling
hiccups exceeding 159 ms — rather than the mean read time. Channel 1 never shows
it because DDR3 gives it seconds of slack.

!!! note "Current best explanation, not a closed case"
    The tail-latency reading fits every measurement above, but has not been
    directly observed. The proposed remedy is
    [doubling the channel-2 FIFO](troubleshooting.md#raising-the-channel-2-fifo);
    re-measure after building rather than assuming.

## Rate tolerance

How far the transmitter may drift off nominal before decoding fails. Measured in
simulation by driving each build at a chip period deliberately off nominal,
chosen not to be a multiple of the 2.5 ns `genClk` tick so edges drift across
the sampling grid. Values are error rates.

| build | −20% | −15% | −10% | −5% | nominal | +5% | +20% |
|---|---|---|---|---|---|---|---|
| Depth 12 (8.33 MHz) | 0.0 | — | — | 0.0 | 0.0 | 0.0 | 0.0 |
| Depth 4 (25 MHz) | **0.38** | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |

8.33 MHz absorbs at least ±20%; 25 MHz breaks between −15% and −20%.

**It is asymmetric — the fast side is dangerous.** The delay line is a fixed
`Depth × 2.5` ns and must be half a chip. Drive the data faster and that fixed
delay grows relative to the shrinking chip until the XOR edge-detect window runs
past the next transition and re-sync collapses. Drive it slower and the window
merely closes early, degrading gracefully.

**It is not simply the ratio.** At −20% both builds sit at identical geometry
(62.5% of a chip), yet Depth 12 decodes and Depth 4 does not. What differs is
granularity: the recovered clock is correctable only in 2.5 ns steps, which is
4.2% of a chip at Depth 12 but 12.5% at Depth 4. Expect tolerance to keep
shrinking as `1 / (2 × Depth)`.

## Timing and simulated rate ceiling

| Depth | Rate | WNS | Sim error rate at nominal |
|---|---|---|---|
| 12 | 8.33 MHz | 0.208 ns | 0.0 |
| 6 | 16.67 MHz | 0.208 ns | 0.0 |
| 5 | 20 MHz | 0.208 ns | 0.0 |
| 4 | 25 MHz | 0.208 ns | 0.0 |
| 3 | 33.33 MHz | 0.208 ns | 0.0 |
| 2 | 50 MHz | 0.208 ns | 0.0 |

Identical WNS at every rate, because the critical path is the DDR3/USB
interface, not the decoder — which still has slack at a 20 ns bit period.

!!! danger "Neither number is a ceiling"
    Timing never becomes the limiting factor, and behavioural simulation has no
    jitter, no analog edge degradation and no Y6/AA6 crosstalk — precisely what
    kills a fast Manchester link, and precisely what eats the tolerance margin
    above. **Only 8.33 MHz has been confirmed on hardware.** The bench ceiling
    must be measured on the bench.

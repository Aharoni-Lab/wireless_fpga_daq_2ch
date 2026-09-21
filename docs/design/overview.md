# Signal chain

Both channels do the same thing, end to end. They used to diverge at the
buffer — channel 1 into DDR3, channel 2 into block RAM — and that asymmetry
explained most of this design's behaviour, including every lost buffer ever
measured on channel 2. It is gone: both channels now cache into DDR3 through
one arbitrated controller.

What remains different is narrower and lives further up: channel 2's half of
the chain is clocked by a recovered clock that stops when its transmitter
does. See [What channel 2 does differently](two-channel.md).

## Inputs

The board has a 200 MHz oscillator (`sysClkp`/`sysClkn`), doubled to a 400 MHz
`genClk` that clocks the decoders. Each channel takes one single-ended 3.3 V
Manchester line:

- **Channel 1** on J2-2 → FPGA pin `Y6`
- **Channel 2** on J2-4 → FPGA pin `AA6`

!!! note "These two pins are a differential pair"
    `Y6` and `AA6` are `B34_L18P` and `B34_L18N` — the most tightly coupled
    trace pair on the connector. Using them as two independent single-ended
    inputs is legal, but expect crosstalk to be the first suspect if the two
    channels interfere at high rates. At 8.33 MHz no crosstalk has been
    observed.

## Per channel

```
manchester ──▶ mandec ──▶ 1→4 bit FIFO ──▶ 4→32 bit FIFO ──▶ [ buffer ] ──▶ okBTPipeOut
                  │                                                              │
               dec_clk (recovered, stalls when idle)                       okClk (USB)
```

`mandec` recovers a clock from the data and emits one bit per recovered edge.
The FIFO chain widens that single bit to the 32-bit words the USB pipe moves.
See [Manchester decoder](decoder.md) for how the recovery works.

## The buffer

Both channels take the same route into and out of DDR3:

```
... ──▶ fifo*_ddr3_in ──▶ [ ddr3_ui ] ──▶ DDR3 (via MIG) ──▶ fifo*_ddr3_out ──▶ pipe
              │                │                                    │
        recovered clock     ui_clk                               ui_clk
```

`ddr3_ui` owns the single MIG user interface and time-shares it between the
two. Each channel gets a ring of its own — 256 MiB, roughly four minutes at
8.33 Mbit/s — in a disjoint half of the address space, and the controller
serves four jobs round-robin: read and write, per channel. There is no fixed
priority, so neither channel can starve the other no matter how backlogged it
gets.

That capacity is the point. A host stall has to last minutes, not
milliseconds, before anything is lost.

!!! note "One controller, so the rings are not the whole device"
    `RING_ADDR_BITS = 26` in `ddr3_ui.v` sets 256 MiB per channel. The rings
    deliberately stop short of the 1 GiB the board carries: a ring only has to
    outlast a host stall, and leaving headroom means the address mapping does
    not have to be exactly what the MIG documentation implies.

### What is still asymmetric

The input FIFO of each channel is written on that channel's recovered clock,
which stalls whenever its decoder is not seeing valid symbols. That is true of
both `fifo_ddr3_in` and `fifo2_ddr3_in`, and it is why both need their resets
sequenced — see [The FIFO reset sequencer](reset-sequencer.md). Channel 1 only
escapes the problem in practice because its transmitter is usually already
streaming when the host resets.

## Host interface

All Opal Kelly endpoints are OR'd into the `okHost` core:

| Endpoint | Direction | Purpose |
|---|---|---|
| `okWireIn` 0x00 | in | resets, see [Pinout](../reference/pinout.md#wirein-0x00) |
| `okBTPipeOut` 0xA0 | out | channel 1 data |
| `okBTPipeOut` 0xA1 | out | channel 2 data |

`okWireOR` is instantiated with `N = 2` and channel 2's endpoint occupies
`okEHx[129:65]`.

## Schematics

The FIFO chain that widens one decoded bit into 32-bit words:

![fifo chain schematic](../imgs/schematics/fifo_chain.png)

The DDR3 cache and its MIG user-interface logic:

![ddr3 schematic](../imgs/schematics/ddr.png)

!!! warning "This schematic predates the two-channel arbiter"
    It shows one input FIFO, one output FIFO and one ring. There are now two
    of each. The MIG side is unchanged.

The Opal Kelly host side, shared by both channels:

![okhost schematic](../imgs/schematics/okhost.png)

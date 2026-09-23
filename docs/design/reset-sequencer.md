# The FIFO reset sequencer

If you modify reset logic, read this first — the failure it prevents is silent,
permanent, and looks like dead hardware.

## The failure

Every FIFO ahead of DDR3 is clocked by a recovered clock, and
[`mandec` stalls that clock when it sees no valid Manchester symbols](decoder.md#clock-recovery).

`fifo_ddr3_in` and `fifo2_ddr3_in` are `fifo_generator` cores with an
**asynchronous reset and the safety circuit enabled**. Such a core needs *both*
of its clocks running to complete a reset. So, without the sequencer:

> Pulse `fifo_reset` while channel 2 is idle, and `fifo2_ddr3_in` never starts
> accepting writes. Nothing ever reaches DDR3, so `fifo2_ddr3_out` stays empty,
> `prog_empty` stays asserted, `ep_ready` never rises,
> `ReadFromBlockPipeOut(0xA1, ...)` blocks forever — **and it does not recover
> when data arrives later.**

On the host that looks like:

```
[mio.streamDaq.fpga_recv] Starting capture from pipe 0xA1
[mio.okDev] Read failed: -1
StreamReadError: Read failed: -1
```

Channel 1 has the same exposure through `fifo_ddr3_in`.

## Why DDR3 did not remove it

DDR3 fixed capacity, and it put the FIFO the host reads (`fifo*_ddr3_out`) on
the free-running `ui_clk`, so a quiet transmitter can no longer freeze a pipe's
readiness. It did not change the input side: `fifo_ddr3_in` and `fifo2_ddr3_in`
are still written on the recovered clocks, so the sequencer is still required.

## The fix

Each channel has its own reset sequencer; the host's reset does not reach these
FIFOs directly:

1. A free-running toggle in each recovered-clock domain,
2. synchronised into `okClk` through an `ASYNC_REG` chain and edge-detected,
3. the channel's FIFO reset is **held until eight recovered-clock edges have
   actually been observed**, then released.

The FIFOs are therefore always reset with their write clock running, and held
across many of its cycles, which is what `fifo_generator` requires.

```verilog
reg dec_fifo_reset  = 1'b1;
reg dec2_fifo_reset = 1'b1;
// ... held until RST_TICKS edges of dec_tick / dec2_tick are seen
```

Toggle-and-synchronise rather than sampling the clock directly, because nothing
should assume the recovered clock is periodic — a half-locked decoder's is not.

### What takes which reset

| FIFO | Reset | Why |
|---|---|---|
| `fifo_chain0/1`, `fifo_ddr3_in` | `dec_fifo_reset` | written on `dec_clk` |
| `fifo2_chain0/1`, `fifo2_ddr3_in` | `dec2_fifo_reset` | written on `dec2_clk` |
| `fifo_ddr3_out`, `fifo2_ddr3_out` | plain `fifo_reset` | both their clocks free-run; gating them would make them depend on a transmitter they do not need |

The two sequencers are **fully independent**. Channel 1 does not wait on a
channel-2 transmitter, so running one channel alone is fine.

## Verification

In simulation, channel 2 through pipe `0xa1`:

| scenario | without sequencer | with sequencer |
|---|---|---|
| ch2 idle during `fifo_reset` | NO DATA (blocked on `ep_ready`) | error rate 0.0 |
| ch2 active during `fifo_reset` | error rate 0.0 | error rate 0.0 |

The default testbench run keeps channel 2 active during the reset. The idle
case — the one hardware actually hits — needs `CH2_RESET_PULSES=0`; see
[Running the testbench](../simulation/testbench.md).

On hardware, starting the capture **before** the channel-2 transmitter streams
cleanly with 0 dropped buffers (confirmed 2026-09-18).

!!! note "A channel without a transmitter stays in reset"
    A channel stays held in reset until its transmitter appears. With no
    channel-2 transmitter connected, `pipe2_ready` on J2-26 sits low and pipe
    `0xA1` returns nothing. That is correct, not a fault.

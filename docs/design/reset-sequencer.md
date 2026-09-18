# The FIFO reset sequencer

This is the change that made channel 2 work. If you modify reset logic, read
this first — the failure it prevents is silent, permanent, and looks like dead
hardware.

## The failure

Every FIFO ahead of DDR3 is clocked by a recovered clock, and
[`mandec` stalls that clock when it sees no valid Manchester symbols](decoder.md#clock-recovery).

`fifo2_out` is a `fifo_generator` core with an **asynchronous reset and the
safety circuit enabled**. Such a core needs *both* of its clocks running to
complete a reset. So:

> Pulse `fifo_reset` while channel 2 is idle, and `fifo2_out` never starts
> accepting writes. `prog_empty` stays asserted, `ep_ready` never rises,
> `ReadFromBlockPipeOut(0xA1, ...)` blocks forever — **and it does not recover
> when data arrives later.**

On the host that looks like:

```
[mio.streamDaq.fpga_recv] Starting capture from pipe 0xA1
[mio.okDev] Read failed: -1
StreamReadError: Read failed: -1
```

Channel 1 escaped this only by luck: its transmitter was always already
streaming when the host reset the board.

## The fix

Each channel now gets its own reset sequencer instead of the host's reset
reaching the FIFOs directly:

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
| `fifo2_chain0/1`, `fifo2_out` | `dec2_fifo_reset` | written on `dec2_clk` |
| `fifo_ddr3_out` | plain `fifo_reset` | both its clocks free-run; gating it would make it depend on a transmitter it does not need |

The two sequencers are **fully independent**. Channel 1 does not wait on a
channel-2 transmitter, so running one channel alone is fine.

## Verification

In simulation, channel 2 through pipe `0xa1`:

| scenario | before | after |
|---|---|---|
| ch2 idle during `fifo_reset` | NO DATA (blocked on `ep_ready`) | error rate 0.0 |
| ch2 active during `fifo_reset` | error rate 0.0 | error rate 0.0 |

Confirmed on hardware 2026-09-18: starting the capture **before** the channel-2
transmitter — the exact condition that used to hang forever — now streams
cleanly with 0 dropped buffers.

!!! note "Expected behaviour change"
    A channel now **stays held in reset until its transmitter appears**, rather
    than idling empty. With no channel-2 transmitter connected, `pipe2_ready`
    on J2-26 sits low and pipe `0xA1` returns nothing. That is correct, not a
    fault.

## Remaining weakness

The sequencer makes reset order irrelevant, but `fifo2_out`'s write clock is
still a recovered clock. The durable fix is to cross out of `dec2_clk` earlier
so the pipe-out FIFO's write side free-runs like channel 1's. Not done; not
currently needed.

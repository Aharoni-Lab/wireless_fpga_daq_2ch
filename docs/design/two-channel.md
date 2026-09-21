# What channel 2 does differently

Channel 2 is a deliberate copy of channel 1 everywhere it can be. This page
lists only the places it is not, and why.

That list used to be led by the buffer. It no longer is: channel 2 caches into
DDR3 through the same controller channel 1 uses. What is left is one real
difference and one historical accident.

## Deliberately identical

| | |
|---|---|
| Decoder | `mandec #(10) dec2` — same parameters as `dec` |
| Data rate | shared `c_shift_ram_0`, so always equal to channel 1 |
| Convention | shared `MANCHESTER_IEEE` localparam |
| FIFO chain | same 1→4 and 4→32 bit widening |
| Buffer | `fifo2_ddr3_in` → DDR3 → `fifo2_ddr3_out`, same IP cores as channel 1 |
| Ring size | 256 MiB, same `RING_ADDR_BITS` |
| `prog_empty` threshold | 16 words, matching `fifo_ddr3_out` exactly |
| Pipe behaviour | `okBTPipeOut`, `ep_ready = ~prog_empty` |

The matched `prog_empty` threshold matters: it is what makes both pipes present
identical readiness semantics to the host, so the same host code drives either.

## Sharing one memory controller

There is one MIG, so `ddr3_ui` arbitrates. Two ring buffers, addressed in
disjoint halves of the space:

```
channel 1   app_addr [0 .. 2^26)
channel 2   app_addr [2^26 .. 2^27)
```

`s_idle` picks between four jobs — write and read, for each channel —
**round-robin**, granting the first ready job at or after a rotating pointer
and then moving the pointer past it. Everything below `s_idle` is the burst
machinery the single-channel version already had, indexed by whichever channel
won.

!!! danger "Round-robin is load-bearing, not tidiness"
    The single-channel `ddr3_ui` used a fixed write-then-read priority. With
    one client that is harmless. With two it is fatal: channel 1's writes and
    reads together keep the controller permanently busy and channel 2 never
    gets a burst. `tb_ddr3_ui` reproduces exactly that — revert the pointer
    update and channel 2 delivers **0** bursts in the time channel 1 delivers
    200.

Bandwidth is not the constraint. Two channels at 8.33 Mbit/s need about
2 MB/s between them, and even this deliberately unpipelined state machine —
several cycles per 32-byte burst — clears that by more than two orders of
magnitude. What the arbiter has to get right is fairness and addressing, not
throughput.

## Necessarily different

### Its write clock can stop

`fifo2_ddr3_in` is written on `dec2_clk`, a recovered clock that stalls
whenever the decoder is not seeing valid Manchester symbols. `fifo_ddr3_in` has
the same property on `dec_clk`; channel 1 only escapes the consequences in
practice because its transmitter is usually already streaming when the host
resets.

This is the whole reason channel 2 needed a reset sequencer — see
[The FIFO reset sequencer](reset-sequencer.md).

!!! note "Moving to DDR3 did not retire the sequencer"
    An earlier version of this page said moving channel 2 onto DDR3 "would not
    have helped", on the grounds that `fifo_ddr3_in` is written on a recovered
    clock just the same. That was right about the reset bug and wrong about
    capacity. The vulnerable FIFO is still there and still needs its reset
    sequenced. What changed is how much data sits behind it.

### It took a debug pin

`AA6` used to be `dbg_sig1`, an **output**. On this design it is an input,
`manchester2`. `dbg_sig1` no longer exists.

!!! danger "Never drive J2-4 while a single-channel bitfile is loaded"
    In the old single-channel builds `AA6` is an output driven by `dec_clk`.
    Connecting a transmitter there means two drivers fighting — on the FPGA and
    on the transmitter. Only load two-channel bitfiles when J2-4 is wired.

## No channel-2 IP to generate

Earlier builds needed `add_ch2_fifo.tcl` to create `fifo_w32_65536_r32_65536`,
a 256 KB block-RAM buffer that existed only on channel 2. Both of channel 2's
FIFOs are now second instances of cores channel 1 already uses —
`fifo_w32_1024_r256_128` and `fifo_w256_128_r32_1024` — so there is nothing to
run per clone, and that script and its `.xci` are deleted.

If you have an older clone whose project still carries the dead core, remove it
from the Vivado Tcl Console:

```tcl
delete_ip [get_ips fifo_w32_65536_r32_65536]
```

It frees roughly 60 of the A75T's 105 block-RAM tiles.

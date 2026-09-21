# Running the testbench

Behavioural simulation of the **full** path — decoder, FIFO chain, clock-domain
crossing, and the real `ReadFromBlockPipeOut` call — against the Opal Kelly and
DDR3 simulation models. No hardware required.

This is how the channel-2 bug was reproduced and how the fix was verified, so
it is worth being able to run.

## Setup

```bash
cd hdl/source/sim
conda env create -f tb_environment.yml
conda activate wireless_fpga_tb
```

Vivado must be installed; `tb_generator.py` finds it at
`C:/Xilinx/Vivado/2023.2/bin/vivado.bat` on Windows or
`/opt/Xilinx/Vivado/2023.1/bin/vivado` otherwise. Override with:

```bash
export VIVADO_PATH=/your/path/to/vivado
```

## Run it

```bash
CH2_ONLY=1 python tb_generator.py
```

Output:

```
channel 2 (pipe 0xa1): error rate 0.0, data length 400
run folder: .../runs/test-1758...
```

`tb_generator.py` renders the testbench from `tb_USBInterface.v.j2`, generates
the Manchester stimulus, runs xsim, then decodes what came back out of the pipe
and scores it.

!!! tip "`CH2_ONLY=1` is the useful mode"
    It skips waiting for DDR3 calibration and the pipe `0xA0` read. **MIG
    calibration does not converge in this simulation** — the DDR3 model reports
    tWLS violations on DQS and `ddr3_init_complete` never asserts — so neither
    channel's DDR3 path can be exercised here.

!!! warning "This testbench no longer covers channel 2's buffer"
    It did, while channel 2's buffer was block RAM. Now that channel 2 caches
    into DDR3 like channel 1, everything from `fifo2_ddr3_in` onward sits
    behind the MIG that will not calibrate. What this testbench still covers
    on channel 2 is the decoder, the FIFO chain and the reset sequencer —
    which is what it was built to find bugs in. The buffer itself is covered
    by [the arbiter testbench](#the-arbiter-testbench) instead.

## How the channels are distinguished

Channel 2 gets a **different payload** from channel 1 on purpose:

```python
seq  = Bits(hex="0x" + "123456789a" * 10)   # channel 1
seq2 = Bits(hex="0x" + "a987654321" * 10)   # channel 2
```

With identical stimulus, cross-wired channels — or a pipe `0xA1` that returned
channel 1's buffer — would pass silently. Both pipes are read from one block in
the testbench, because `ReadFromBlockPipeOut` writes into a shared `pipeOut`
array and two concurrent readers would corrupt each other.

## Watchdog

`ep_ready` comes from `prog_empty`, so a pipe that never reaches its threshold
blocks the read forever. The testbench fails loudly after `TIMEOUT_NS` instead
of hanging with no output:

```
TIMEOUT: no $finish after 8000000 ns.
  A pipe read is most likely still blocked waiting on ep_ready.
```

That message is the signature of the [reset-ordering bug](../design/reset-sequencer.md).

## Waveforms

```bash
vivado -mode batch -source runs/test-<timestamp>/show_waveform.tcl
```

When chasing a channel-2 problem, look at `dec2_clk`, `dec2_fifo_reset` and
`fifo2_ddr3_out`'s `prog_empty`.

## The arbiter testbench

`hdl/source/sim/tb_ddr3_ui.v` is a separate, much smaller testbench for
`ddr3_ui`, the block that shares the one MIG between both channels.

It exists because of the calibration problem above. The full testbench has
never been able to reach DDR3, so when channel 2 moved behind the MIG the new
arbitration logic would otherwise have had **no** simulation coverage at all.
This replaces the MIG with a behavioural model of its user interface — not a
DDR3 model, just the `app_*` handshake, with pseudo-random `app_rdy` and
`app_wdf_rdy` stalls so the retry paths are exercised — and runs in seconds.

```bash
cd hdl/source/sim
xvlog ../design/ddr3/ddr3_ui.v tb_ddr3_ui.v
xelab work.tb_ddr3_ui -s tb_ddr3_ui_sim
xsim tb_ddr3_ui_sim -runall
```

```
ch1 delivered 200/200 words
ch2 delivered 200/200 words
at first completion: ch1 200, ch2 199
ring slots per channel: 4
PASS
```

What it checks:

| | |
|---|---|
| Round trip | every word each channel writes comes back, in order |
| Isolation | each word carries a channel tag; arriving on the wrong sink fails |
| Addressing | every burst must address its own channel's ring, asserted per command |
| Ring wrap | `RING_ADDR_BITS` is overridden to 5 — **4 burst slots per ring** — so both rings wrap tens of times and sit at full for most of the run |
| Fairness | neither channel may take more than twice the other's bursts |

!!! tip "Fairness has to be sampled mid-run"
    The obvious check — compare the final delivered counts — is worthless
    here, and passed a deliberately broken fixed-priority arbiter. Both
    channels always finish: once the greedy one's source drains, the starved
    one gets the whole controller and catches up. The testbench snapshots both
    counts at the moment the *first* channel completes instead. Under fixed
    priority that reads **200 to 0**.

!!! note "Both failure modes were confirmed to fail it"
    Before trusting the pass, the arbiter was broken two ways on purpose —
    collapsing both rings onto one address range, and replacing round-robin
    with fixed priority — and the testbench caught each. A test that has never
    been seen to fail is not evidence.

## Two traps that have already cost time

!!! warning "Convention mismatch scores ~30%, not 0%"
    The generator must encode according to `MANCHESTER_IEEE`. When it did not,
    every recovered bit came back complemented — but the score was a *plausible*
    30% rather than an obvious 100%, because the preamble `0x0f0f0f0f` inverts
    to `0xf0f0f0f0`, which contains the same 16-bit search pattern shifted by
    four bits. `shift_to_preamble` locked onto the inverted preamble and scored
    partial garbage. `check_channel` now tests the inverted stream too and names
    a convention mismatch explicitly.

!!! warning "A passing simulation is not a passing bitfile"
    A behavioural model has ideal clocks. Every rate up to 50 MHz decodes
    perfectly here, and that says nothing about jitter, analog edges or Y6/AA6
    crosstalk on real hardware.

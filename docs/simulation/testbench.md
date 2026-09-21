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
python tb_generator.py
```

Output:

```
Cannot find preamble
channel 1 (pipe 0xa0): error rate 0.0, data length 400
Cannot find preamble
channel 2 (pipe 0xa1): error rate 0.0, data length 400
run folder: .../runs/test-1790...
```

`tb_generator.py` renders the testbench from `tb_USBInterface.v.j2`, generates
the Manchester stimulus, runs xsim, then decodes what came back out of both
pipes and scores each.

!!! note "`Cannot find preamble` there is correct output"
    It comes from the *inverted* copy of the stream, which `check_channel`
    scores as well to catch a Manchester convention mismatch. When the stream
    decodes correctly, the inverted one contains no preamble — so this line
    appearing exactly once per channel, next to an error rate of 0.0, is the
    healthy case. Its absence would be the thing to look at.

## The memory controller is a model

Both channels now cache into DDR3, and **MIG calibration does not converge in
this simulation** — the Micron model reports tWLS violations on DQS and
`init_calib_complete` never asserts within any simulated time anyone has been
willing to wait. Left alone, that would make everything behind the controller
invisible here, which after channel 2 moved onto DDR3 meant *both* channels.

So the default run swaps the controller, not the design:
`hdl/source/sim/ddr3/mig_ui_model.sv` replaces `xem7310_a75_mig` behind a
`SIM_MIG_MODEL` define that is set on the simulation fileset only. The arbiter,
all four DDR3 FIFOs, the reset sequencer and both Opal Kelly pipes are the ones
that go into the bitfile.

!!! success "Channel 1 is simulatable for the first time"
    Before this, `CH2_ONLY=1` was the only usable mode and pipe `0xA0` had
    never returned data in simulation. Both pipes now do.

| variable | effect |
|---|---|
| *(default)* | both channels, MIG replaced by the behavioural model |
| `CH2_ONLY=1` | skips the calibration wait and the pipe `0xA0` read — roughly halves the runtime when only channel 2 matters |
| `REAL_MIG=1` | the actual MIG and the Micron DDR3 model. **Does not work**; kept so the calibration problem can be reproduced |

!!! warning "What the model does not prove"
    It is a model of the MIG's *user interface*, not of DDR3. No refresh, no
    bank or row timing, no bandwidth limit, no read/write reordering. It says
    the logic driving `app_*` is correct. It says nothing about whether the
    controller is configured correctly or meets DDR3 timing — those stay
    hardware questions, which is why the acceptance criteria in
    [Measurements](../reference/measurements.md#two-channel-capture) are bench
    measurements.

    What it *is* deliberately awkward about: `app_rdy` and `app_wdf_rdy` are
    withheld pseudo-randomly, so a design that only works against an
    always-ready controller fails here.

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

The two are complementary, not redundant. The full testbench proves the whole
path works; this one reaches the states the full testbench cannot. Its
stimulus is 400 bits per channel — nowhere near enough to wrap a ring, fill
one, or hold both channels backlogged long enough for starvation to show. This
one shrinks the rings to **4 burst slots** so all of that happens in
microseconds, and it runs in seconds rather than minutes.

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

!!! warning "The DDR3 calibration wait was bound to a debug pin"
    The testbench waited on `ddr3_init_complete`, which is just the net wired
    to `dbg_sig2` — and `dbg_sig2` only carries `init_calib_complete` when
    `DEBUG_MODE` is 0. The committed default is 1, where it carries `dec2_clk`.
    So the wait was satisfied the moment channel 2's decoder ticked and never
    actually waited for calibration. It is now a hierarchical reference to
    `dut.init_calib_complete`, which cannot drift with the debug pin mapping.

!!! warning "A passing simulation is not a passing bitfile"
    A behavioural model has ideal clocks. Every rate up to 50 MHz decodes
    perfectly here, and that says nothing about jitter, analog edges or Y6/AA6
    crosstalk on real hardware.

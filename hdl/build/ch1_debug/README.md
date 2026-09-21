# Channel-1 debug bitfiles

**Not committed** (this folder is covered by the `hdl/build/**/*` ignore rule),
and **not the same as the bitfiles one directory up**, despite having identical
filenames. miniscope-io parses the filename scheme and it has no slot for a
variant, so the only way to tell these apart is which folder they came from.

Same design, same nine data rates, same FIFO reset fix as the committed set. The
only difference is which three signals reach the debug pins.

**These are all pre-2026-09-21 builds**, so every one of them carries the old
128 KB block-RAM `fifo2_out`. The source tree no longer has that FIFO at all —
channel 2 caches into a 256 MiB DDR3 ring. Regenerate before using any of them
to reason about channel-2 buffer loss; the number you would measure is from a
design that no longer exists.

| pin | committed set (`../`) | this set |
|---|---|---|
| J3-10 (F4) | `dec_clk` — ch1 recovered clock | `dec_clk` — ch1 recovered clock |
| J2-18 (Y1) | `dec2_clk` — ch2 recovered clock | **`dec_data_bit`** — ch1 recovered data |
| J2-26 (AA14) | `pipe2_ready` — ch2 pipe ready | **`pipe_ready`** — ch1 pipe ready (0xA0) |

So this set puts the whole channel-1 chain on the pins — clock, then data, then
pipe — which is what you want when testing how fast channel 1 can run. It tells
you *which stage* failed instead of just that the capture came back empty:

- **no clock on J3-10** — the decoder never locked at that rate. Nothing
  downstream can work. Suspect the rate, the signal quality, or the transmitter.
- **clock fine, J2-26 never goes high** — it locked but the buffer path is stuck.
- **all three healthy but the data is wrong** — it locked and buffered, so look
  at the decode itself. If the *starts* of buffers are corrupt, try increasing the
  dummy words.

Built from `DEBUG_MODE = 2` in `USBInterface.v`; the committed default is `1`.
To regenerate: set it to `2`, then

    vivado -mode batch -source hdl/build/build_bitfile.tcl -tclargs <Depth> ch1_debug

Each `.bit` has a `.txt` beside it with the shift depth, git commit, and timing.

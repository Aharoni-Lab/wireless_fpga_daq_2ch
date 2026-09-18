# Manchester decoder bitfiles at different data rates

Nine bitfiles for the Opal Kelly XEM7310, same design, different input data
rates: 8.33, 10, 12.5, 14.29, 16.67, 20, 25, 33.33 and 50 MHz.

We currently run everything at 8.33 MHz. We would like to know how far up the
rate can actually go on real hardware, and we can't answer that ourselves right
now. If you can try some of these on your setup, that would be a big help.

## What is different between them: exactly one number

The decoder recovers the clock from the Manchester signal by comparing the
incoming signal against a slightly delayed copy of itself. That delay has to be
a quarter of a bit period. It is built from a shift register clocked at 400 MHz,
so it can only be set in steps of 2.5 ns.

The length ("Depth") of that shift register is the **only** thing that differs
between these nine files:

    data rate = 100 MHz / Depth

| file | Depth | rate |
|---|---|---|
| `USBInterface-8_33mhz-...` | 12 | 8.33 MHz  <- what we use today |
| `USBInterface-10mhz-...` | 10 | 10 MHz |
| `USBInterface-12_5mhz-...` | 8 | 12.5 MHz |
| `USBInterface-14_29mhz-...` | 7 | 14.29 MHz |
| `USBInterface-16_67mhz-...` | 6 | 16.67 MHz |
| `USBInterface-20mhz-...` | 5 | 20 MHz |
| `USBInterface-25mhz-...` | 4 | 25 MHz |
| `USBInterface-33_33mhz-...` | 3 | 33.33 MHz |
| `USBInterface-50mhz-...` | 2 | 50 MHz |

Everything else is identical: same decoder, same buffers, same USB endpoints,
same pins, same Manchester convention (IEEE, i.e. 01 = 1 and 10 = 0).

Because the step is a whole number, the available rates get coarse at the top —
there is nothing between 25 and 33.33 MHz, for instance.

**The FPGA does not detect the rate.** Pick the file that matches your
transmitter.

## How much rate error it tolerates

From simulation, driving the decoder deliberately off its nominal rate:

- at 8.33 MHz it still decodes perfectly at ±20%
- at 25 MHz it is fine at −15% and breaks at −20%

So the margin shrinks as the rate goes up. A transmitter running **fast** is the
dangerous direction — the fixed delay becomes too long compared to the now
shorter bit. Running slow degrades gently. Above 25 MHz we have not measured it,
and we expect it to be tighter still.

## What we know and what we don't

All nine decode perfectly **in simulation** at their nominal rate, right up to
50 MHz. Please don't read that as "50 MHz works". Simulation has no jitter, no
analog edge rounding and no crosstalk, and those eat exactly the margin above.

**Only 8.33 MHz has ever been confirmed on real hardware.** Everything faster is
untested. Finding where it actually breaks is the whole point of sending these.

## The debug pins — worth wiring a scope to one of them

Three pins, all carrying channel-1 signals:

| pin | signal | what it tells you |
|---|---|---|
| J3-10 (F4) | recovered clock | **the important one.** Ticking = the decoder locked. Dead = it never locked at that rate |
| J2-18 (Y1) | recovered data bit | the decoded bitstream, valid on the clock above |
| J2-26 (AA14) | pipe ready | the buffer has data for the host |

If a rate does not work, these tell you *which stage* failed, which an empty
capture cannot:

- **no clock on J3-10** — the decoder never locked at that rate. Nothing
  downstream can possibly work. This is the interesting failure.
- **clock fine but J2-26 never goes high** — it locked, but the buffer path is
  stuck.
- **all three healthy, data still wrong** — it locked and buffered fine, so the
  problem is in the decoding itself. See the dummy words section below.

## One other thing that might surprise you

These bitfiles have two input channels. **J2-2 (FPGA pin Y6) is channel 1 and is
the one to use** — it comes out on USB pipe `0xA0`, and it is the validated path.

There is also a channel 2 on J2-4 reading out on pipe `0xA1`. It is still being
debugged at our end and you can ignore it entirely — just leave J2-4
unconnected. A channel with no transmitter stays held in reset by design, so
nothing bad happens.

## Our main suspicion if the higher rates misbehave: dummy words

Worth understanding the mechanism, because it makes this quite likely.

There is a gap between frame buffers where nothing is being transmitted. This
decoder recovers its clock from the transitions in the signal itself, and when
the transitions stop, the recovered clock stops with them. So at the start of
every frame the decoder has to re-acquire lock from scratch.

The dummy words at the head of each buffer (10 words of 4 bytes on our side) are
what pays for that re-acquisition: they are sacrificial, and real payload only
starts once the decoder has settled.

The faster the link runs, the less clean the signal is, and the more bits the
decoder needs before it settles. At some rate the existing 10 words stop being
enough and the front of every buffer gets eaten.

So **if you see the starts of buffers corrupted at the higher rates, increase the
dummy words before concluding the rate itself is unusable.** Knowing whether that
recovers it, and how many words it takes, is probably the single most useful
thing to come out of this.

(For completeness: we also added logic that holds a channel in reset until its
recovered clock is actually running. That costs a few clock edges once, at reset
or when a transmitter first appears — it is not a per-frame cost and does not eat
into the dummy words.)

## What would help most coming back

- Which rates work and which don't on your setup
- Recorded data for whichever rates you manage, raw captures are fine
- The transmitter rate you actually used, measured if you can
- Whether increasing the dummy words changes anything at the higher rates
- If a rate fails, a scope trace of J3-10 (channel 1 recovered clock) would tell
  us a lot — in particular whether it was ticking at all

Each `.bit` has a `.txt` beside it recording exactly how it was built — shift
depth, git commit, and timing numbers.

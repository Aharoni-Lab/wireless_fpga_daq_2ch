# Host side (miniscope-io)

Capture is handled by **[miniscope-io](https://github.com/miniscope/mio)** — `mio` on the command line. It
uploads the bitfile, resets the board, reads a pipe, and writes video, metadata
and raw binary.

!!! note "The bitfile lives in miniscope-io, not here"
    `mio` loads bitfiles from `mio/devices/XEM7310-A75/` in its own checkout.
    Copy the file you want from `hdl/build/` into that directory, keeping the
    name unchanged — miniscope-io parses it, and its test suite checks the
    format.

!!! warning "Two-channel support is not in upstream miniscope-io yet"
    `pipe_addr`, the `-ch1-alt` / `-ch2-alt` configs and
    `capture_both_channels.py` described below are not merged into
    miniscope-io's main branch yet.

Both channels arrive over **one USB cable**. The FPGA exposes them as two
separate block-pipe endpoints, so the host opens the board once and chooses
which endpoint to read.

| Channel | Pin | Endpoint |
|---|---|---|
| 1 | J2-2 | `0xA0` |
| 2 | J2-4 | `0xA1` |

## Selecting a channel

miniscope-io carries a `pipe_addr` field on the stream config, defaulting to
`0xA0` so existing configs are unchanged:

```yaml
bitstream: "XEM7310-A75/USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit"
pipe_addr: 0xA1     # channel 2; 0xA0 is channel 1
```

The two-channel configs:

| Config id | Endpoint | Pin |
|---|---|---|
| `wireless-200px-ch1-alt` | 0xA0 | J2-2 |
| `wireless-200px-ch2-alt` | 0xA1 | J2-4 |

```bash
mio stream capture -c wireless-200px-ch2-alt -b -o my_recording
```

The two configs differ **only** in that one line, so swapping them changes the
channel and nothing else.

## Recording both at once

Two `mio stream capture` processes **cannot** share the board: `OpenBySerial`
takes exclusive USB ownership, and a second process would re-flash the bitfile
and pulse resets, killing the first stream.

Instead, one process holds the handle and alternates between the two endpoints,
writing each to its own raw `.bin`. `capture_both_channels.py` in miniscope-io
does this; decode each file afterwards through the normal pipeline:

```bash
STREAMDAQ_MOCKRUN=1 PYTEST_OKDEV_DATA_FILE=both-ch1.bin \
    mio stream capture -c wireless-200px-ch1-alt -o ch1 --no-display
```

`STREAMDAQ_MOCKRUN=1` makes miniscope-io read from a file instead of the board,
which gives full frames, metadata CSV and video from a raw capture.

!!! note "No live display of both channels yet"
    Nothing in the hardware prevents it — `StreamDaq` simply assumes one device,
    one pipe, one display. Simultaneous live view needs one process running two
    decode pipelines.

## What to expect

Per channel at 8.33 Mbit/s with 200×200 px frames:

- 8 buffers per frame, ~20 fps
- buffers 0–6 carry 5032 px, buffer 7 carries 4776 — together exactly 40000 px
- a `pixel_count` of 4776 on the last buffer of a frame is **normal**, not a
  short read

Verify a capture by checking `buffer_count` increments by 1 and
`dropped_buffer_count` stays 0.

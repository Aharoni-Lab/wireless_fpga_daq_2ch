# wireless_fpga_daq_2ch

Two independent Manchester receivers on one Opal Kelly XEM7310-A75, for the
wireless miniscope project. Two miniscopes, one FPGA, one USB cable.

**📖 Full documentation: <https://aharoni-lab.com/wireless_fpga_daq_2ch/>**

Status: 8.33 MHz works on hardware — two miniscopes streaming at once, both
channels buffered in DDR3. The other rates still have to be rebuilt and run.

| | Channel 1 | Channel 2 |
|---|---|---|
| Input pin | J2-2 (`Y6`) | J2-4 (`AA6`) |
| Buffering | DDR3, 256 MiB ring | DDR3, 256 MiB ring |
| USB endpoint | `0xA0` | `0xA1` |

Both channels share one delay line, so they always run at the same data rate.

## Quick start

Recording is done with [miniscope-io (`mio`)](https://github.com/miniscope/mio), which flashes the bitfile and
reads the stream. Its two-channel support (`pipe_addr` and the `-ch1-alt` /
`-ch2-alt` configs) is not merged upstream yet.

Copy `hdl/build/USBInterface-8_33mhz-J2_2+J2_4-3v3-IEEE.bit` — the only rate
confirmed on hardware — into `mio/devices/XEM7310-A75/` in your miniscope-io
checkout, then:

```bash
mio stream capture -c wireless-200px-ch2-alt -b -o my_recording
```

Rebuild at another rate (argument is the shift depth, `rate = 100 / Depth` MHz):

```bash
vivado -mode batch -source hdl/build/build_bitfile.tcl -tclargs 12
```

## Layout

```
hdl/source/design/    RTL: USBInterface.v (top), mandec/, ddr3/, okHDL/, xem7310.xdc
hdl/source/sim/       Testbench generator and simulation models
hdl/source/board/     XEM7310-A75 board files incl. mig.prj
hdl/build/            Vivado project, IP sources, build scripts, bitfiles
docs/                 Documentation site (MkDocs)
```

## Docs locally

```bash
pip install mkdocs-material && mkdocs serve
```

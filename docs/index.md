# Two-channel wireless FPGA DAQ

Two independent Manchester-encoded data streams received simultaneously on one
Opal Kelly XEM7310-A75, for the wireless miniscope project. Each channel carries
one miniscope; both arrive over a single USB cable.

!!! success "Status"
    **8.33 MHz works on hardware**: two miniscopes streaming at once, both
    channels buffered in DDR3. The other rates still have to be rebuilt and
    run on hardware — see [The bitfiles](build/bitfiles.md).

## What this is

The original DAQ decoded **one** Manchester stream. This design adds a second,
fully independent receiver on a pin that used to be a debug output, so one
XEM7310 serves two transmitters.

| | Channel 1 | Channel 2 |
|---|---|---|
| Input pin | J2-2 (FPGA `Y6`) | J2-4 (FPGA `AA6`) |
| Decoder | `mandec dec` | `mandec dec2` |
| Buffering | FIFO chain → **DDR3** → FIFO | FIFO chain → **DDR3** → FIFO |
| USB endpoint | `okBTPipeOut` **0xA0** | `okBTPipeOut` **0xA1** |

Both channels share one `c_shift_ram_0` delay line, so **they always run at the
same data rate**. That rate is set at build time — see
[Building a bitfile](build/building.md).

They also share the one DDR3 controller, arbitrated round-robin between them,
each with a 256 MiB ring of its own — see
[Sharing one memory controller](design/overview.md#sharing-one-memory-controller).

## Where to start

- Never touched this before → [Signal chain](design/overview.md)
- Just need a bitfile → [The bitfiles](build/bitfiles.md)
- Want to record data → [Host side](host/capture.md), using [miniscope-io](https://github.com/miniscope/mio)
- Something is broken → [Troubleshooting](reference/troubleshooting.md)
- Changing the rate or the RTL → [Building a bitfile](build/building.md)

## Repository layout

```
hdl/source/design/    RTL: USBInterface.v (top), mandec/, ddr3/, okHDL/, xem7310.xdc
hdl/source/sim/       Testbench generator and Opal Kelly / DDR3 simulation models
hdl/source/board/     XEM7310-A75 board files, incl. mig.prj for the DDR3 controller
hdl/build/            Vivado project, IP .xci sources, build scripts, built bitfiles
hdl/build/ch1_debug/  Same builds with channel-1 debug signals on the spare pins
docs/                 This site
```

!!! note "Every bitfile records its source"
    Each committed bitfile has a `.txt` beside it recording the git commit,
    shift depth and timing slack it was built from. Only the 8.33 MHz file is
    built from the current source — see [The bitfiles](build/bitfiles.md).

# Vivado setup

One-time setup on a Windows machine. Budget 2–3 hours, mostly downloading.

## Install

1. Get **Vivado ML Standard 2023.2** from the
   [AMD download page](https://www.xilinx.com/support/download.html), under
   "Vivado Archive". Free, no licence file. A free AMD account is required.
2. The project file is tied to the **2023.x** series — a different major version
   will not open it cleanly.
3. In *Customize → Devices*, untick everything except **Artix-7**. That takes
   the install from ~100 GB to roughly 30 GB. The XEM7310-A75 is an Artix-7.
4. Leave *Install Cable Drivers* ticked.
5. Install to a short path with no spaces, e.g. `C:\Xilinx`.
6. Install [Git for Windows](https://git-scm.com/download/win) if not present.

## Open the project

```
File ▸ Open Project ▸ hdl\build\wireless_daq.xpr
```

If prompted to upgrade IP cores, click **Upgrade** / *Report IP Status* then
*Upgrade Selected*. This is normal.

!!! warning "Known snag: missing `mig.prj`"
    The DDR3 controller IP points at a board-store copy of `mig.prj` in the
    home directory of whoever generated it
    (`.Xilinx/Vivado/2023.1.1/xhub/board_store/…`). If Vivado reports
    `mig.prj` not found:

    1. In *Sources*, find `xem7310_a75_mig`, right-click ▸ *Re-customize IP*.
    2. Point it at
       `hdl\source\board\OpalKelly\XEM7310-A75\1.0\1.0\mig.prj`
       (this repo ships it).
    3. Click through with defaults and OK.

## Prove the toolchain

Before changing anything, build the tree as-is and confirm you get a bitfile
with non-negative WNS and WHS. If that fails, the environment is the problem,
not the design.

```
vivado -mode batch -source hdl/build/build_bitfile.tcl -tclargs 12
```

Then continue to [Building a bitfile](building.md).

# %% import and definition
import os
import subprocess
import time

import numpy as np
import pandas as pd
from bitstring import BitArray, Bits
from jinja2 import Environment, FileSystemLoader
from routine.data_utils import resolve_error, shift_to_preamble

# Half-bit (chip) period of the generated stimulus, in ns. This MUST match the
# build: the decoder's chip period is Depth * 5 ns (Depth 10 -> 50, which is why
# 50 was the historical default). Driving a rate the build was not made for is a
# legitimate experiment -- it measures rate tolerance -- but it is not a test of
# whether the decoder works, so set it deliberately.
HALF_PRD = int(os.environ.get("HALF_PRD", 50))
PRJ_FILE = "../../build/wireless_daq.xpr"
TB_TEMP_FILE = "./tb_USBInterface.v.j2"
TCL_TEMP_FILE = "./run_tb.tcl.j2"
WAVE_TEMP_FILE = "./show_waveform.tcl.j2"
RUN_FOLDER = "./runs"
WCFG_FILE = "./tb_USBInterface_behav.wcfg"
OK_HOST = "./okSim/okHostCalls.vh"
BOARD_PATH = "../board/"
VLIB_FILES = [
    "./okSim/okWireOR.v",
    "./ddr3/ddr3_model.sv",
    "./ddr3/mig_ui_model.sv",
    "./okSim/okHost.v",
    "./okSim/okWireIn.v",
    "./ddr3/wiredly.v",
    "./okSim/okBTPipeOut.v",
]
VIVADO_PATH = os.environ.get(
    "VIVADO_PATH",
    (
        "C:/Xilinx/Vivado/2023.2/bin/vivado.bat"
        if os.name == "nt"
        else "/opt/Xilinx/Vivado/2023.1/bin/vivado"
    ),
)
# Simulation gives up after this long in simulated ns. A blocked pipe read
# would otherwise hang the run indefinitely.
#
# A healthy CH2_ONLY run finishes on its own at about 350_000 ns, so the default
# only ever matters when something is wrong -- and then it costs roughly three
# hours of wall time to reach. Override it when you are deliberately running a
# failing case and only need to see that no data came out:
#     TIMEOUT_NS=1500000 CH2_ONLY=1 CH2_RESET_PULSES=0 python tb_generator.py
TIMEOUT_NS = int(os.environ.get("TIMEOUT_NS", 8_000_000))
# REAL_MIG=1 instantiates the actual MIG and the Micron DDR3 model instead of
# mig_ui_model. It does not currently work and is kept only so the calibration
# problem can be reproduced: the model reports tWLS violations on DQS and
# init_calib_complete never asserts, within any simulated time anyone has been
# willing to wait. Everything behind the memory controller is invisible in that
# mode -- which, once channel 2 moved onto DDR3, meant both channels.
#
# The default swaps the controller for a behavioural model of its user
# interface. The arbiter, all four DDR3 FIFOs, the reset sequencer and both
# pipes are the real ones; only the external memory controller is a model.
# See hdl/source/sim/ddr3/mig_ui_model.sv.
REAL_MIG = os.environ.get("REAL_MIG", "0") == "1"
# CH2_ONLY=1 skips the wait for DDR3 calibration and the pipe 0xa0 read. With
# the model in place calibration does complete, so this is no longer needed to
# get a usable run -- it just halves the runtime when only channel 2 is of
# interest. With REAL_MIG=1 it is the only mode that reaches any pipe at all,
# and even then only as far as fifo2_ddr3_in.
CH2_ONLY = os.environ.get("CH2_ONLY", "0") == "1"
# CH2_RESET_PULSES=0 removes the channel-2 activity that the testbench drives
# while fifo_reset is asserted. Hardware has no equivalent -- nothing guarantees
# a transmitter is sending on J2-4 when the host pulses the reset wire-in -- so
# setting this to 0 reproduces the hardware reset ordering in simulation.
CH2_RESET_PULSES = os.environ.get("CH2_RESET_PULSES", "1") == "1"

# %% handle paths


def abspath(*parts):
    r"""Absolute path, always with forward slashes.

    These paths get interpolated into Tcl and Verilog string literals, where a
    backslash is an escape character -- on Windows a native path such as
    ...\hdl\build\wireless_daq.xpr reaches Vivado as "hdluild" because \b is a
    backspace. Vivado and xsim accept forward slashes on every platform.
    """
    return os.path.abspath(os.path.join(*parts)).replace(os.sep, "/")


cur_run = os.path.join(RUN_FOLDER, "test-{}".format(int(time.time())))
infile = abspath(cur_run, "stimulus.csv")
infile2 = abspath(cur_run, "stimulus2.csv")
outfile = abspath(cur_run, "output.csv")
outfile2 = abspath(cur_run, "output2.csv")
vfile = abspath(cur_run, TB_TEMP_FILE.rstrip(".j2"))
tcl_file = abspath(cur_run, TCL_TEMP_FILE.rstrip(".j2"))
wdb_file = abspath(cur_run, "waveform.wdb")
wcfg_file = abspath(WCFG_FILE)
wave_file = abspath(cur_run, WAVE_TEMP_FILE.rstrip(".j2"))
okhost_file = abspath(OK_HOST)
vlib = [abspath(f) for f in VLIB_FILES]
prj_file = abspath(PRJ_FILE)
board_path = abspath(BOARD_PATH)
cleanup_path = abspath(os.path.dirname(prj_file), "wireless_daq.srcs", "sim_autogen")
os.makedirs(cur_run, exist_ok=True)

# %% generate input
preamble = Bits(hex="0x0f0f0f0f")


# Must match `localparam MANCHESTER_IEEE` in hdl/source/design/USBInterface.v.
# IEEE 802.3 encodes a 1 as the chip pair 01 and a 0 as 10; "normal" is the
# reverse. The decoder recovers pair[0] under IEEE and pair[1] under normal, so
# encoding with the wrong convention makes every recovered bit come back
# inverted -- see check_channel below for why that used to look like a 30%
# error rate rather than an obvious total mismatch.
MANCHESTER_IEEE = True


def manchester_stimulus(seq_bits):
    """Encode preamble+payload as the half-bit pairs the tb feeds in."""
    data = preamble + seq_bits
    one, zero = ("01", "10") if MANCHESTER_IEEE else ("10", "01")
    return pd.DataFrame(
        {
            "time": np.full(len(data) * 2, HALF_PRD),
            "data": list("".join([one if s else zero for s in data])),
        }
    )


seq = Bits(hex="0x" + "123456789a" * 10)
# Channel 2 gets a different payload on purpose: if the two channels were
# cross-wired, or if pipe 0xa1 returned channel 1's buffer, checking channel 2
# against seq2 fails instead of passing on channel 1's data.
seq2 = Bits(hex="0x" + "a987654321" * 10)
manchester_stimulus(seq).to_csv(infile, header=None, index=None)
manchester_stimulus(seq2).to_csv(infile2, header=None, index=None)

# %% render templates
tb_env = Environment(loader=FileSystemLoader(os.path.dirname(TB_TEMP_FILE)))
tcl_env = Environment(
    loader=FileSystemLoader(os.path.dirname(TCL_TEMP_FILE)),
    variable_start_string="<<=",
    variable_end_string="=>>",
)
wave_env = Environment(
    loader=FileSystemLoader(os.path.dirname(WAVE_TEMP_FILE)),
    variable_start_string="<<=",
    variable_end_string="=>>",
)
tb_temp = tb_env.get_template(os.path.basename(TB_TEMP_FILE))
tcl_temp = tcl_env.get_template(os.path.basename(TCL_TEMP_FILE))
wave_temp = wave_env.get_template(os.path.basename(WAVE_TEMP_FILE))
tb_temp.stream(
    STIMULUS_FNAME=infile,
    STIMULUS2_FNAME=infile2,
    OUTPUT_FNAME=outfile,
    OUTPUT2_FNAME=outfile2,
    OKHOST_PATH=okhost_file,
    TIMEOUT_NS=TIMEOUT_NS,
    WAIT_FOR_DDR3=not CH2_ONLY,
    READ_CH1=not CH2_ONLY,
    CH2_RESET_PULSES=CH2_RESET_PULSES,
    HALF_PRD=HALF_PRD,
).dump(vfile)
tcl_temp.stream(
    VLIB=" ".join(vlib + [vfile]),
    DEFINES="" if REAL_MIG else "SIM_MIG_MODEL",
    PRJ=prj_file,
    CLEANUP_PATH=cleanup_path,
    BOARD_PATH=board_path,
    WDB_PATH=wdb_file,
).dump(tcl_file)
wave_temp.stream(WDB_FILE=wdb_file, WCFG_FILE=wcfg_file).dump(wave_file)

# %% run commands
# Step 1: Vivado renders the xsim scripts but does not run them (-scripts_only
# in run_tb.tcl). launch_simulation cannot spawn its own compile.bat on Windows
# here; it fails immediately with "Spawn failed: Broken pipe" whether or not a
# console is attached and with a sanitised PATH. The generated .bat scripts run
# perfectly when invoked directly, so we invoke them ourselves below.
with open(os.path.join(cur_run, "tb_run.log"), "w") as log_file:
    subprocess.run(
        (
            VIVADO_PATH,
            "-nolog",
            "-nojournal",
            "-mode",
            "batch",
            "-source",
            str(tcl_file),
        ),
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )

# Step 2: run compile / elaborate / simulate ourselves. The scripts call xvlog,
# xelab and xsim unqualified, so Vivado's bin directory has to be on PATH.
sim_script_dir = abspath(
    os.path.dirname(prj_file), "wireless_daq.sim", "sim_autogen", "behav", "xsim"
)
bat_env = dict(os.environ)
bat_env["PATH"] = os.path.dirname(VIVADO_PATH) + os.pathsep + bat_env.get("PATH", "")

for step in ("compile", "elaborate", "simulate"):
    script = os.path.join(sim_script_dir, step + (".bat" if os.name == "nt" else ".sh"))
    if not os.path.exists(script):
        raise SystemExit(
            "{} script not generated: {}\nCheck {} for Vivado errors.".format(
                step, script, os.path.join(cur_run, "tb_run.log")
            )
        )
    print("running {} step...".format(step))
    log_path = os.path.join(cur_run, step + ".log")
    with open(log_path, "w") as log_file:
        if os.name == "nt":
            cmd = ("cmd", "/c", script)
        else:
            cmd = ("sh", script)
        proc = subprocess.run(
            cmd,
            cwd=sim_script_dir,
            env=bat_env,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
    if proc.returncode != 0:
        with open(log_path) as log_file:
            errors = [ln for ln in log_file if ln.startswith("ERROR")]
        raise SystemExit(
            "{} step failed (exit {}). First errors:\n{}\nFull log: {}".format(
                step, proc.returncode, "".join(errors[:10]) or "  (none)", log_path
            )
        )

# %% check result
pre = preamble[16:]


def check_channel(label, path, expected):
    with open(path, "r") as of:
        line = of.readline()
    if not line.strip():
        print("{}: NO DATA -- pipe returned nothing".format(label))
        return None
    out_data = BitArray(bin=line)

    def rate_for(bits):
        arr = shift_to_preamble(bits, pre, last=True)[
            len(pre) : len(pre) + len(expected)
        ]
        return resolve_error(arr, expected)[3], resolve_error(arr, expected)[4]

    err_rate, arr_len = rate_for(out_data)
    # The preamble 0x0f0f0f0f inverts to 0xf0f0f0f0, which contains the same
    # 16-bit search pattern shifted by four bits. So a fully inverted stream
    # still locks onto a "preamble" and scores a plausible partial error rate
    # instead of an obvious 100%. Check the inverted stream before believing a
    # middling number: a clean decode there means the stimulus and the RTL
    # disagree about MANCHESTER_IEEE, not that the hardware path is broken.
    inv_rate, inv_len = rate_for(~out_data)
    if inv_rate is not None and err_rate is not None and inv_rate < err_rate:
        print(
            "{}: error rate {} -- but INVERTED decodes at {}. "
            "Convention mismatch: MANCHESTER_IEEE in tb_generator.py does not "
            "match USBInterface.v.".format(label, err_rate, inv_rate)
        )
        return inv_rate
    print("{}: error rate {}, data length {}".format(label, err_rate, arr_len))
    return err_rate


if CH2_ONLY:
    print("CH2_ONLY: channel 1 not exercised (needs DDR3 calibration)")
    rate1 = None
else:
    rate1 = check_channel("channel 1 (pipe 0xa0)", outfile, seq)
rate2 = check_channel("channel 2 (pipe 0xa1)", outfile2, seq2)
print("run folder: {}".format(os.path.abspath(cur_run)))

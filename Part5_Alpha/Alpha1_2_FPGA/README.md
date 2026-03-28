# Alpha Submission - Systolic Array + FSM + FPGA Integration

This alpha implements a systolic MAC array with a control FSM that:
1. Streams activations and weights from an external XMEM buffer,
2. Executes all MAC operations on-chip,
3. Performs accumulation using a ROM-driven schedule, and
4. Writes the final 4x4 output feature map into a result BRAM (RES).

The design can be validated **either** via RTL simulation **or** on an FPGA (XEM7310 + Opal Kelly FrontPanel). The FPGA path is included for completeness but is not required to verify correctness since it is complicated to configure the FPGA ecosystem.

---

## 1. Repository layout

Key files:

- `top_ok_core.v`  
  Top-level RTL with:
  - Opal Kelly host interface (okHost, WireIn, WireOut, PipeIn, PipeOut),
  - XMEM dual-port BRAM (activations + weights),
  - RES dual-port BRAM (final outputs),
  - `core_fsm` instance (control state machine),
  - `core` instance (MAC array, FIFOs, PMEM, SFU).

- `core_fsm.v`  
  Control FSM:
  - Sequences kernel loading, activation streaming, MAC execution, writeback, and accumulation.
  - Interfaces with XMEM (read), PMEM (intermediate storage), ROM (acc schedule), and RES (final write).

- `core.v`  
  Datapath wrapper for:
  - Input FIFO (`ififo` / L0),
  - `mac_array`,
  - Output FIFO (`ofifo`),
  - PMEM SRAM,
  - SFU (ReLU + accumulation input path).

- `rom.v`  
  Hard-coded ROM storing the accumulation scan pattern.

- `sram_xmem_32b_w2048_dp.v`  
  Dual-port BRAM model for XMEM (32-bit x 2048).

- `sram_128b_w16_dp.v`  
  Dual-port BRAM model for RES (128-bit x 16).

- `top_ok_core_tb.v`  
  Testbench that:
  - Loads `activation.txt` and `weight_k*.txt` into XMEM,
  - Pulses `start`,
  - Waits for `done`,
  - Reads back RES and compares against `out.txt`.

- `compiled/activation.txt`  
- `compiled/weight_k1.txt` … `weight_k9.txt`  
- `compiled/out.txt`  
  Stimulus and golden outputs (matching the original project spec).

- `284_controller.py`  
  Python + Opal Kelly FrontPanel script to:
  - Configure the FPGA,
  - Load activations/weights via PipeIns,
  - Start the FSM,
  - Poll `done`,
  - Read RES via PipeOut, and
  - Compare against `out.txt`.

---

## 2. Dependencies / Environment

**RTL simulation:**
- Vivado 2024.1 (or similar)
- All RTL files above in the same project

**FPGA validation:**
- Board: Opal Kelly XEM7310-A200
- Opal Kelly FrontPanel installed (Python API `ok.py` available)
- Vivado-generated bitfile: `top_ok_core.bit`
- Python 3.8+  
- `284_controller.py` placed with correct paths:
  - `BITFILE` pointing to `top_ok_core.bit`
  - `BASE_DIR` pointing to the `compiled/` folder

---

## 3. How to run: RTL simulation (recommended for grading)

1. **Create a Vivado project**  
   - Add the following source files:
     - `top_ok_core.v`
     - `core_fsm.v`
     - `core.v`
     - `rom.v`
     - `sram_xmem_32b_w2048_dp.v`
     - `sram_128b_w16_dp.v`
     - Any submodules used by `core` (FIFOs, MAC array, SFU, PMEM wrapper).
   - Add `top_ok_core_tb.v` as a simulation source.
   - Make sure the working directory or file paths allow the TB to see:
     - `compiled/activation.txt`
     - `compiled/weight_k1.txt` … `weight_k9.txt`
     - `compiled/out.txt`

2. **Set `top_ok_core_tb` as simulation top**.

3. **Run behavioral simulation**.  
   The testbench will:
   - Reset the design,
   - Write all activations into XMEM[0 .. 35],
   - Write all 9 kernels into XMEM starting from `W_BASE = 1024`,
   - Pulse `start`,
   - Wait until `fsm_done` is asserted,
   - Read all RES entries and compare them to `out.txt`.

4. **Expected output (simulation log)**  
   In the simulation transcript you should see per-output messages of the form:
   - For matching outputs:
     ```text
     xx-th output featuremap Data matched! :D
     ```
   - On complete success:
     ```text
     ############ No error detected ##############
     ########### Project Completed !! ############
     ```

Any mismatch will print the FPGA RES value and the golden `answer` for debugging.

---

## 4. How to run: FPGA + Opal Kelly (complicated & Xilinx board required)

1. **Program the FPGA**
   - Generate the bitstream `top_ok_core.bit` 
   - FrontPanel IS required, comprehensive documentation is at: <docs.opalkelly.com>
     - Python API and DLLs need to be in same dir as the python controller.
     - HDL API needs to be included in Vivado project.
     - Constraints file is also required, but can be auto-generated at <pins.opalkelly.com>
   - The script will automatically load the bitstream to the FPGA if in same dir.
   - The top-level `top_ok_core` uses:
     - `okUH`, `okHU`, `okUHU`, `okAA` for the FrontPanel host interface,
     - `okClk` as the main system clock (100 MHz in this configuration).

2. **Check endpoint mapping**
   - `WireIn  0x00` - Control register  
     - Bit 0: `start`  
     - Bit 1: `reset`
   - `WireOut 0x30` - Status  
     - Bit 0: `done` (FSM done flag)
   - `PipeIn  0x80` - Activations → XMEM activations region  
   - `PipeIn  0x81` - Weights → XMEM weights region (starting at `W_BASE`)  
   - `PipeOut 0xA0` - RES readback (128-bit entries as 4x32-bit words)

3. **Run the Python driver**
   - Ensure `BITFILE` and `BASE_DIR` in `284_controller.py` are set correctly.
   - From a shell:
     ```bash
     python 284_controller.py
     ```

4. **Expected console output (Python)**
   Typical successful run:
   ```text
   Opening & configuring FPGA...
   Resetting core...
   Loading activations...
   Loading weights...
   Starting compute...
   FSM reports done.
   Reading RES data from FPGA...
   Loading golden out.txt...
   Comparing results...
   [01] MATCH
   [02] MATCH
   ...
   [16] MATCH
   ############ No error detected ############
   ########### Project Completed !! ###########

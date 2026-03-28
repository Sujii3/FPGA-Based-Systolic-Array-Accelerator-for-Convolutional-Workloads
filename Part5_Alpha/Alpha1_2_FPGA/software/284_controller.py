# Python-side driver 
# Uses Opal Kelly FrontPanel API to:
#   1) Reset core
#   2) Load activations into XMEM via PipeIn 0x80
#   3) Load weights (k1..k9) into XMEM via PipeIn 0x81
#   4) Pulse start
#   5) Poll for done
#   6) Read results from RES via PipeOut
#   7) Compare vs out.txt like the Verilog TB
#

import time
import struct
from pathlib import Path

import ok  # Opal Kelly FrontPanel Python API


# WireIn: control
EP_WI_CONTROL = 0x00

# Control bits
BIT_CONTROL_START = 1 << 0
BIT_CONTROL_RESET = 1 << 1

# WireOut: status / done 
EP_WO_STATUS = 0x30
BIT_STATUS_DONE = 1 << 0  # status[0] = done

# PipeIns: activations & weights 
EP_PI_ACT = 0x80
EP_PI_W   = 0x81

# PipeOut: RES readback.
EP_PO_RES = 0xA0  

# Problem size 
BW        = 4
PSUM_BW   = 16
LEN_KIJ   = 9      # 3×3 kernels
LEN_ONIJ  = 16     # 4×4 output feature map positions
COL       = 8
ROW       = 8
LEN_NIJ   = 36     # 6×6 input feature map positions

# Each RES entry is 128b = 4×32b words
WORDS_PER_RES = 4

# Default paths 
BITFILE  = r"C:\Users\saxen\OneDrive\Desktop\fpga\top_ok_core.bit"  
BASE_DIR = Path(r"C:\Users\saxen\Downloads\284FinalProject\Part1\compiled") 


class OKTop:
    def __init__(self, bitfile: str, serial: str = ""):
        self.dev = ok.okCFrontPanel()
        self.bitfile = bitfile
        self.serial = serial

    # Device init
    def open_and_configure(self):
        if self.dev.OpenBySerial(self.serial) != 0:
            raise RuntimeError("Failed to open Opal Kelly device; check USB / power / serial.")
        self.dev.ResetFPGA()
        err = self.dev.ConfigureFPGA(self.bitfile)
        if err != 0:
            raise RuntimeError(f"ConfigureFPGA failed with error code {err}")
        # Let things settle
        time.sleep(0.05)

    # Control helpers
    def _set_control(self, start: bool = False, reset: bool = False):
        val = 0
        if start:
            val |= BIT_CONTROL_START
        if reset:
            val |= BIT_CONTROL_RESET
        self.dev.SetWireInValue(EP_WI_CONTROL, val)
        self.dev.UpdateWireIns()

    def pulse_reset(self, hold_time_s: float = 0.001):
        self._set_control(reset=True, start=False)
        time.sleep(hold_time_s)
        self._set_control(reset=False, start=False)

    def pulse_start(self):
        # momentary start pulse
        self._set_control(start=True, reset=False)
        # small delay not strictly necessary
        time.sleep(0.001)
        self._set_control(start=False, reset=False)

    def wait_done(self, timeout_s: float = 2.0) -> bool:
        """Poll WireOut for done bit."""
        t0 = time.time()
        while time.time() - t0 < timeout_s:
            self.dev.UpdateWireOuts()
            status = self.dev.GetWireOutValue(EP_WO_STATUS)
            print(status)
            if status & BIT_STATUS_DONE:
                return True
            time.sleep(0.001)
        return False

    # Pipe helpers
    def write_pipe_in_words32(self, addr: int, words):
        """Send a list/iterable of 32-bit words to a PipeIn endpoint."""
        words = list(words)
        n = len(words)
        if n == 0:
            return

        # Pack to a contiguous bytearray; SWIG wants a buffer it can treat as char*
        buf = bytearray(4 * n)
        off = 0
        for w in words:
            w &= 0xFFFFFFFF
            struct.pack_into('<I', buf, off, w)  # little-endian 32b
            off += 4

        # Now buf is perfectly acceptable to okCFrontPanel_WriteToPipeIn
        self.dev.WriteToPipeIn(addr, buf)

    def read_pipe_out_words32(self, addr: int, n_words: int):
        """
        Read n_words of 32-bit data from a PipeOut endpoint.
        Returns a list[int].
        """
        if n_words <= 0:
            return []
        n_bytes = n_words * 4
        raw = self.dev.ReadFromPipeOut(addr, n_bytes)
        if len(raw) != n_bytes:
            raise RuntimeError(f"ReadFromPipeOut returned {len(raw)} bytes, expected {n_bytes}")

        words = []
        for i in range(n_words):
            (w,) = struct.unpack_from('<I', raw, 4 * i)
            words.append(w)
        return words

    # File loaders
    @staticmethod
    def _load_file_as_words32(path: Path):
        """
        Parse a text file with:
          - 3 header/comment lines
          - then one 32-bit binary value per line (%32b)
        Returns list[int].
        """
        words = []
        with open(path, 'r') as f:
            # skip first three comment lines
            _ = f.readline()
            _ = f.readline()
            _ = f.readline()
            for line in f:
                line = line.strip()
                if not line:
                    continue
                # binary string to int
                w = int(line, 2)
                words.append(w)
        return words

    @staticmethod
    def _load_out_vectors128(path: Path, n_vec: int):
        """
        Parse out.txt:
          - 3 header lines
          - then n_vec lines of %128b
        Returns list[int] of 128-bit ints.
        """
        vecs = []
        with open(path, 'r') as f:
            _ = f.readline()
            _ = f.readline()
            _ = f.readline()
            for _ in range(n_vec):
                line = f.readline()
                if not line:
                    raise RuntimeError("Not enough lines in out.txt")
                line = line.strip()
                if not line:
                    raise RuntimeError("Empty line in out.txt where data expected")
                vecs.append(int(line, 2))
        return vecs

    # High-level operations
    def load_activations(self, path: Path):
        """
        Load activations into XMEM via PipeIn 0x80.
        Order: exactly as in activation.txt (36 words).
        """
        words = self._load_file_as_words32(path)
        if len(words) != LEN_NIJ:
            print(f"Warning: expected {LEN_NIJ} activation words, got {len(words)}")
        self.write_pipe_in_words32(EP_PI_ACT, words)

    def load_weights(self, base_dir: Path):
        """
        Load 9 kernels (weight_k1.txt .. weight_k9.txt) sequentially
        into XMEM via PipeIn 0x81. The top-level HDL increments
        weight_wr_addr starting at W_BASE, so just stream them
        in order.
        """
        all_words = []
        for kij in range(1, LEN_KIJ + 1):
            fname = f"weight_k{kij}.txt"
            path = base_dir / fname
            words = self._load_file_as_words32(path)
            if len(words) != COL:
                print(f"Warning: {fname}: expected {COL} words, got {len(words)}")
            all_words.extend(words)

        if len(all_words) != LEN_KIJ * COL:
            print(f"Warning: total weight words = {len(all_words)}, expected {LEN_KIJ * COL}")

        self.write_pipe_in_words32(EP_PI_W, all_words)

    def start_and_wait(self, timeout_s: float = 2.0):
        """
        Pulse start and wait for done bit from core_fsm.
        """
        self.pulse_start()
        if not self.wait_done(timeout_s=timeout_s):
            raise TimeoutError("Timeout waiting for FSM done")

    def read_results_from_res(self, n_outputs: int = LEN_ONIJ):
        """
        Reads RES contents via PipeOut, assuming:
          - RES has n_outputs entries of 128 bits each
          - Each entry is output as 4×32-bit words on PipeOut in order
            [w0, w1, w2, w3] (least significant chunk first).
        Returns list[int] each a 128-bit integer, with bits aligned in the
        same order as the %128b in out.txt:
            vec = {w3, w2, w1, w0}.
        """
        total_words = n_outputs * WORDS_PER_RES
        words = self.read_pipe_out_words32(EP_PO_RES, total_words)

        results = []
        idx = 0
        for _ in range(n_outputs):
            w0 = words[idx]
            w1 = words[idx + 1]
            w2 = words[idx + 2]
            w3 = words[idx + 3]
            idx += 4

            # Build 128-bit value: concatenate [w3, w2, w1, w0]
            vec = ((w3 & 0xFFFFFFFF) << 96) | \
                  ((w2 & 0xFFFFFFFF) << 64) | \
                  ((w1 & 0xFFFFFFFF) << 32) | \
                  (w0 & 0xFFFFFFFF)
            results.append(vec)

        return results


# Main test flow
def main():
    bitfile = BITFILE
    base = BASE_DIR

    print("Opening & configuring FPGA...")
    ok_top = OKTop(bitfile)
    ok_top.open_and_configure()

    print("Resetting core...")
    ok_top.pulse_reset()

    # Load activations
    print("Loading activations...")
    ok_top.load_activations(base / "activation.txt")

    # Load weights
    print("Loading weights...")
    ok_top.load_weights(base)

    # Start FSM
    print("Starting compute...")
    ok_top.start_and_wait(timeout_s=5.0)
    print("FSM reports done.")

    # Read back results
    print("Reading RES data from FPGA...")
    fpga_results = ok_top.read_results_from_res(n_outputs=LEN_ONIJ)

    # Load golden
    print("Loading golden out.txt...")
    golden = OKTop._load_out_vectors128(base / "out.txt", n_vec=LEN_ONIJ)

    # Compare
    print("Comparing results...")
    errors = 0
    for i, (got, exp) in enumerate(zip(fpga_results, golden), start=1):
        if got == exp:
            print(f"[{i:02d}] MATCH")
        else:
            print(f"[{i:02d}] MISMATCH")
            print(f"     FPGA : {got:0128b}")
            print(f"     GOLD : {exp:0128b}")
            errors += 1

    if errors == 0:
        print("############ No error detected ############")
        print("########### Project Completed !! ###########")
    else:
        print(f"Total mismatches: {errors}")


if __name__ == "__main__":
    main()

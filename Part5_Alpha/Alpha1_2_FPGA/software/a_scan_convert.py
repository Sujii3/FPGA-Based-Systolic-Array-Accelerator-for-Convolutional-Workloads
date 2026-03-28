#!/usr/bin/env python3
import sys

def emit_case_statements(filename):
    try:
        with open(filename, "r") as f:
            lines = f.read().split()
    except FileNotFoundError:
        print(f"ERROR: Could not open file '{filename}'")
        sys.exit(1)

    for idx, b in enumerate(lines):
        # Skip empty lines
        if not b:
            continue

        # Validate binary string
        if set(b) - {"0", "1"}:
            print(f"WARNING: Skipping invalid binary string: {b}")
            continue

        # Convert to integer
        val = int(b, 2)

        # Print Verilog case entry: address is 11 bits, data as 11-bit hex
        print(f"8'b{format(idx, f'0{8}b')}: data <= 11'b{b};")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python generate_cases.py <input_file>")
        sys.exit(1)

    emit_case_statements(sys.argv[1])

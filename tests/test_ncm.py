# Copyright 2026 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""Native framing and descriptor checks; no simulator or USB hardware required."""

import subprocess

import pytest


@pytest.mark.parametrize(
    "program,case",
    [
        ("test_ncm_ntb", "round_trips"),
        ("test_ncm_ntb", "malformed"),
        ("test_ncm_ntb", "chained_ndps"),
        ("test_ncm_ntb", "receive_datagram_limit"),
        ("test_ncm_ntb", "mutation_tests"),
        ("test_ncm_descriptors", "fs"),
        ("test_ncm_descriptors", "hs"),
    ],
    ids=[
        "ntb-round-trips",
        "ntb-malformed",
        "ntb-chained-ndps",
        "ntb-datagram-limit",
        "ntb-20000-mutations",
        "descriptors-fs",
        "descriptors-hs",
    ],
)
def test_native_ncm(native_binaries, program, case):
    result = subprocess.run(
        [str(native_binaries[program]), case],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"{program} {case} failed ({result.returncode})\n"
        f"{result.stdout}\n{result.stderr}"
    )
    assert result.stdout.strip() == f"PASS: {case}"

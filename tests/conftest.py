# Copyright 2026 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

"""Build the portable C checks once per pytest session, with a native compiler."""

import os
from pathlib import Path
import subprocess

import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--sanitizers",
        action="store_true",
        help="Build native helpers with address and undefined-behaviour sanitizers",
    )


def run_checked(command, timeout, env=None):
    result = subprocess.run(
        command, capture_output=True, text=True, timeout=timeout, check=False,
        env=env,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {command}\n"
        f"{result.stdout}\n{result.stderr}"
    )
    return result.stdout


@pytest.fixture(scope="session")
def native_binaries(request, tmp_path_factory):
    source = Path(__file__).resolve().parent
    build = tmp_path_factory.mktemp("ncm_native")
    binary_dir = build / "bin"
    command = [
        "cmake",
        "-S", str(source),
        "-B", str(build),
        "-DCMAKE_BUILD_TYPE=Debug",
        f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY={binary_dir}",
        f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG={binary_dir}",
        f"-DNCM_SANITIZERS={'ON' if request.config.getoption('sanitizers') else 'OFF'}",
    ]
    # Do not inherit an XTC CC=xcc for these native-only tests.
    env = {key: value for key, value in os.environ.items() if key != "CC"}
    compiler = os.environ.get("HOST_CC", "cc" if os.name != "nt" else None)
    if compiler:
        command.append(f"-DCMAKE_C_COMPILER={compiler}")
    run_checked(command, timeout=120, env=env)
    run_checked(["cmake", "--build", str(build), "--config", "Debug"], timeout=120, env=env)
    suffix = ".exe" if os.name == "nt" else ""
    return {
        name: binary_dir / (name + suffix)
        for name in ("test_ncm_ntb", "test_ncm_descriptors")
    }

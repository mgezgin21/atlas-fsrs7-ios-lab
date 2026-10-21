#!/usr/bin/env python3
"""Fail BEFORE a slow Flutter build if the resolved Runner linker omits Rust."""
import json
import re
import subprocess
import sys
from pathlib import Path

SYMBOLS = (
    "atlas_fsrs7_engine_version", "atlas_fsrs7_abi_version",
    "atlas_fsrs7_parameter_count", "atlas_fsrs7_state_size",
    "atlas_fsrs7_output_size", "atlas_fsrs7_next",
)

def main():
    if len(sys.argv) != 4 or sys.argv[2] not in ("simulator", "device"):
        raise SystemExit("Usage: verify_xcode_link.py ios/Runner.xcodeproj simulator|device Debug|Release")
    project, variant, configuration = sys.argv[1:]
    sdk = "iphonesimulator" if variant == "simulator" else "iphoneos"
    archive = Path(project).resolve().parent / "NativeRust" / variant / "libatlas_fsrs7_probe.a"
    if not archive.is_file() or archive.stat().st_size == 0:
        raise SystemExit(f"Missing Rust archive for {variant}: {archive}")
    base = ["xcodebuild", "-project", project, "-target", "Runner", "-configuration", configuration,
            "-sdk", sdk, "-showBuildSettings"]
    result = subprocess.run(base + ["-json"], text=True, capture_output=True)
    if result.returncode == 0:
        try:
            blocks = json.loads(result.stdout)
            match = [b for b in blocks if b.get("target") == "Runner"]
            if len(match) != 1:
                raise ValueError("Expected exactly one Runner target")
            settings = match[0].get("buildSettings", {})
            flags = settings.get("OTHER_LDFLAGS", "")
            if isinstance(flags, list):
                flags = " ".join(map(str, flags))
        except (ValueError, KeyError, TypeError) as exc:
            raise SystemExit(f"Invalid Runner Xcode JSON settings: {exc}")
    else:
        result = subprocess.run(base, text=True, capture_output=True)
        if result.returncode:
            raise SystemExit("Xcode failed to show resolved build settings:\n" + result.stderr[-4000:])
        found = re.findall(r"(?m)^\s*OTHER_LDFLAGS\s*=\s*(.+)$", result.stdout)
        if not found:
            raise SystemExit("Xcode emitted no resolved OTHER_LDFLAGS")
        flags = found[-1]
    expected = f"NativeRust/{variant}/libatlas_fsrs7_probe.a"
    incorrect = f"NativeRust/{'device' if variant == 'simulator' else 'simulator'}/libatlas_fsrs7_probe.a"
    missing = [x for x in (expected, "-force_load", *("_"+s for s in SYMBOLS)) if x not in flags]
    if missing or incorrect in flags:
        raise SystemExit(f"BAD RUNNER LINK SETTINGS: variant={variant}; missing={missing}; wrong archive={incorrect in flags}; flags={flags}")
    print(f"IOS_RUNNER_EFFECTIVE_LINK_SETTINGS=PASS;VARIANT={variant};CONFIGURATION={configuration};SYMBOLS={len(SYMBOLS)}")

if __name__ == "__main__":
    main()

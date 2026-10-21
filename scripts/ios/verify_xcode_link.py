#!/usr/bin/env python3
"""Validate the *resolved* Xcode Runner link contract BEFORE Flutter compiles.

Fails closed on missing Rust -L directory, wrong archive, wrong architecture,
missing six -u exports, or an unresolvable build configuration.
"""
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


def run(*args):
    value = subprocess.run(args, text=True, capture_output=True)
    if value.returncode:
        raise SystemExit(
            f"Command failed ({value.returncode}): {' '.join(args)}\n"
            f"{value.stdout[-2000:]}\n{value.stderr[-4000:]}"
        )
    return value.stdout


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in ("simulator", "device"):
        raise SystemExit(
            "Usage: verify_xcode_link.py ios/Runner.xcodeproj simulator|device Debug|Release"
        )

    project, variant, configuration = sys.argv[1:]
    sdk = "iphonesimulator" if variant == "simulator" else "iphoneos"
    project_path = Path(project).resolve()
    native_dir = project_path.parent / "NativeRust" / variant
    archive = native_dir / "libatlas_fsrs7_probe.a"
    if not archive.is_file() or archive.stat().st_size == 0:
        raise SystemExit(f"Rust archive missing or empty: {archive}")

    # Xcode's simulator Debug defaults may link both host x86_64 and arm64.
    # Verify the archive contains BOTH, rather than waiting for a late ld error.
    archs = set(run("xcrun", "lipo", "-archs", str(archive)).split())
    required = {"arm64", "x86_64"} if variant == "simulator" else {"arm64"}
    if not required.issubset(archs):
        raise SystemExit(
            f"Rust archive architecture mismatch: {archive}; "
            f"required={sorted(required)} actual={sorted(archs)}"
        )
    if variant == "device" and "x86_64" in archs:
        raise SystemExit("Device archive unexpectedly contains simulator x86_64")

    args = [
        "xcodebuild", "-project", str(project_path),
        "-target", "Runner", "-configuration", configuration,
        "-sdk", sdk, "-showBuildSettings",
    ]
    settings = {}
    response = subprocess.run(args + ["-json"], capture_output=True, text=True)
    if response.returncode == 0:
        try:
            blocks = json.loads(response.stdout)
            matching = [block for block in blocks if block.get("target") == "Runner"]
            if len(matching) == 1:
                settings = matching[0].get("buildSettings", {})
        except (json.JSONDecodeError, TypeError, KeyError):
            pass
    if not settings.get("OTHER_LDFLAGS") or not settings.get("LIBRARY_SEARCH_PATHS"):
        plain = run(*args)
        for key in ("OTHER_LDFLAGS", "LIBRARY_SEARCH_PATHS"):
            match = re.findall(rf"(?m)^\s*{key}\s*=\s*(.*)$", plain)
            if match:
                settings[key] = match[-1]

    def flatten(value):
        if isinstance(value, list):
            return " ".join(map(str, value))
        return str(value or "")

    flags = flatten(settings.get("OTHER_LDFLAGS"))
    libdirs = flatten(settings.get("LIBRARY_SEARCH_PATHS"))
    required_flags = ["-u", *("_" + symbol for symbol in SYMBOLS)]
    missing = [flag for flag in required_flags if flag not in flags]
    if missing:
        raise SystemExit(f"Runner missing Rust export retention flags: {missing}; got: {flags}")

    # The prior CI run reached ld -latlas_fsrs7_probe WITHOUT -L NativeRust.
    # Strict resolved-path check catches it here, before the slow Flutter build.
    expected_dir = str(native_dir)
    if expected_dir not in libdirs and f"NativeRust/{variant}" not in libdirs:
        raise SystemExit(
            f"Runner library search directory not resolved: expected={expected_dir}; "
            f"actual={libdirs}"
        )
    wrong = "device" if variant == "simulator" else "simulator"
    if f"NativeRust/{wrong}" in libdirs:
        raise SystemExit(f"Wrong Rust variant also in library search path: {libdirs}")

    pbxproj = (project_path / "project.pbxproj").read_text(encoding="utf-8")
    expected_file = f"NativeRust/{variant}/libatlas_fsrs7_probe.a"
    if expected_file not in pbxproj:
        raise SystemExit(f"Runner does not reference Rust archive: {expected_file}")

    print(
        f"IOS_RUNNER_PREFLIGHT=PASS;VARIANT={variant};CONFIGURATION={configuration};"
        f"ARCHS={','.join(sorted(archs))};LINK_SEARCH_PATH=PASS;"
        f"EXPORT_FLAGS={len(SYMBOLS)};FRAMEWORK_ARCHIVE=PASS"
    )


if __name__ == "__main__":
    main()

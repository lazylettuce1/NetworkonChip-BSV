#!/usr/bin/env python3
"""Build source snapshots and collect only metrics from passing testbenches."""

import argparse
import csv
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


BENCHES = {
    "router": ("mkTbNocRouter", "TbNocRouter.bsv", ("router_latency",)),
    "basic": ("mkTbNocBasic", "TbNocBasic.bsv", ("L0", "B_S")),
    "router-perf": ("mkTbNocRouterPerf", "TbNocRouterPerf.bsv", ("B_R",)),
    "network-perf": ("mkTbNocNetworkPerf", "TbNocNetworkPerf.bsv", ("B_N",)),
}
CSV_FIELDS = (
    "label", "benchmark", "metric", "packets", "payload_bytes", "cycles",
    "bytes_per_cycle", "injected_cycle", "collected_cycle",
    "clock_period_ns", "latency_ns", "bytes_per_second",
)


class CheckFailed(Exception):
    pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bsc", default="bsc", help="BSC executable or absolute path")
    parser.add_argument("--bsc-flag", action="append", default=[],
                        help="Extra compiler flag; e.g. --bsc-flag=-aggressive-conditions")
    parser.add_argument("--label", default="baseline", help="Configuration label in the CSV")
    parser.add_argument("--build-dir", default="build-metrics")
    parser.add_argument("--tests", nargs="+", choices=BENCHES, default=list(BENCHES))
    parser.add_argument("--warmup", type=int, default=1000)
    parser.add_argument("--cycles", type=int, default=10000, help="B_R/B_N measurement window")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--clock-period-ns", type=Decimal,
                        help="Optional achieved clock period for physical-unit conversions")
    args = parser.parse_args()
    if args.warmup < 0 or args.cycles <= 0:
        parser.error("warmup must be nonnegative and cycles must be positive")
    if args.warmup + args.cycles + 10032 >= 2**32:
        parser.error("the run must fit in the 32-bit cycle counter")
    if not 0 <= args.seed < 2**32:
        parser.error("seed must fit in 32 bits")
    if args.clock_period_ns is not None and args.clock_period_ns <= 0:
        parser.error("clock-period-ns must be positive")
    bsc = shutil.which(args.bsc)
    if bsc is None:
        parser.error("bsc was not found; run in your BSC container or pass --bsc /path/to/bsc")
    bsc = str(Path(bsc).resolve())

    source = Path(__file__).resolve().parent
    build_root = Path(args.build_dir).resolve()
    build_root.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=build_root))
    build = run_dir / "build"
    rtl = run_dir / "rtl"
    build.mkdir()
    rtl.mkdir()
    source_hashes = {}
    for filename in sorted(source.glob("*.bsv")):
        shutil.copy2(filename, run_dir / filename.name)
        source_hashes[filename.name] = hashlib.sha256(filename.read_bytes()).hexdigest()

    env = dict(os.environ)
    env["PATH"] = str(Path(bsc).parent) + os.pathsep + env.get("PATH", "")
    records = []
    manifest = {
        "label": args.label, "bsc": bsc, "flags": args.bsc_flag,
        "warmup": args.warmup, "window": args.cycles, "seed": args.seed,
        "clock_period_ns": str(args.clock_period_ns) if args.clock_period_ns else None,
        "source_sha256": source_hashes, "status": "running", "completed": [],
    }

    def save_results():
        (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        with (run_dir / "metrics.csv").open("w", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=CSV_FIELDS)
            writer.writeheader()
            writer.writerows(records)

    def run_command(name, command, simulation=False):
        print(name + "...", flush=True)
        result = subprocess.run(command, cwd=run_dir, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = run_dir / (name + ".log")
        log.write_text("COMMAND: " + json.dumps(command) + "\n" + result.stdout)
        # BSV $finish status is not consistently the process exit status.
        failed = result.returncode != 0 or re.search(r"\bFAIL\b", result.stdout)
        if simulation or failed:
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n", flush=True)
        if failed:
            raise CheckFailed(name + " failed; see " + str(log))
        if simulation and not re.search(r"\bPASS\b|ALL TESTS PASSED", result.stdout):
            raise CheckFailed(name + " ended without a PASS marker; see " + str(log))
        return result.stdout

    def metric_record(benchmark, name, values):
        row = {"label": args.label, "benchmark": benchmark, "metric": name}
        row.update({key: value for key, value in values.items() if key in CSV_FIELDS})
        if "payload_bytes" in values:
            rate = Decimal(values["payload_bytes"]) / Decimal(values["cycles"])
            row["bytes_per_cycle"] = str(rate)
        if args.clock_period_ns is not None:
            row["clock_period_ns"] = str(args.clock_period_ns)
            if "payload_bytes" in values:
                row["bytes_per_second"] = str(rate * Decimal(10**9) / args.clock_period_ns)
            else:
                row["latency_ns"] = str(Decimal(values["cycles"]) * args.clock_period_ns)
        return row

    print("Source snapshot, build logs, and results: " + str(run_dir), flush=True)
    save_results()
    definitions = ["-D", "METRIC_WARMUP=" + str(args.warmup),
                   "-D", "METRIC_WINDOW=" + str(args.cycles),
                   "-D", "METRIC_SEED=" + str(args.seed)]
    try:
        run_command("rtl", [bsc, "-u", "-verilog", *args.bsc_flag,
                            "-bdir", str(build), "-vdir", str(rtl), "-info-dir", str(build),
                            "-g", "mkNoc", "Noc.bsv"])
        for benchmark in args.tests:
            module, filename, expected = BENCHES[benchmark]
            executable = build / module
            run_command(benchmark + "-compile", [bsc, "-u", "-sim", *args.bsc_flag,
                        *definitions, "-bdir", str(build), "-simdir", str(build),
                        "-info-dir", str(build), "-g", module, filename])
            run_command(benchmark + "-link", [bsc, "-sim", "-bdir", str(build),
                        "-simdir", str(build), "-e", module, "-o", str(executable)])
            output = run_command(benchmark + "-sim", [str(executable)], simulation=True)
            found = {}
            for line in output.splitlines():
                match = re.fullmatch(r"METRIC (\w+) (.+)", line)
                if match:
                    name, fields = match.groups()
                    found[name] = dict(re.findall(r"(\w+)=([^\s]+)", fields))
            for match in re.finditer(
                r"^--- (\w+) = (\d+) cycles ---\n"
                r"[ \t]*Injected: cycle (\d+) \| Collected: cycle (\d+)$",
                output, re.MULTILINE,
            ):
                name, cycles, injected, collected = match.groups()
                found[name] = {"cycles": cycles, "injected_cycle": injected,
                               "collected_cycle": collected}
            for match in re.finditer(
                r"^--- (\w+) = (\d+\.\d+) bytes/cycle ---\n"
                r"[ \t]*(\d+) packets \| (\d+) payload bytes \| (\d+) cycles$",
                output, re.MULTILINE,
            ):
                name, rate, packets, payload_bytes, cycles = match.groups()
                found[name] = {"bytes_per_cycle": rate, "packets": packets,
                               "payload_bytes": payload_bytes, "cycles": cycles}
            for name in expected:
                if name not in found:
                    raise CheckFailed(benchmark + " passed without the " + name + " measurement")
            records.extend(metric_record(benchmark, name, found[name]) for name in expected)
            manifest["completed"].append(benchmark)
            save_results()
        manifest["status"] = "passed"
    except (CheckFailed, OSError) as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error)
        save_results()
        print(str(error), file=sys.stderr)
        print("Only completed, passing benchmarks are included in " + str(run_dir / "metrics.csv"),
              file=sys.stderr)
        return 1
    save_results()
    print("Verified measurements: " + str(run_dir / "metrics.csv"), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

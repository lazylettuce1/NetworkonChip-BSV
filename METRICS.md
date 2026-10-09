# Performance measurements

These additions observe the existing router/NoC interfaces. `NocRouter.bsv`,
`Noc.bsv`, and `NocTypes.bsv` are not changed by the metric helpers or runner.

| Quantity | Experiment | Timing/counting boundary |
| --- | --- | --- |
| `L0` | The original single-packet test in `TbNocBasic.bsv` | Actual `(0,0)` put firing to first `(3,3)` collection; the collector is always enabled. |
| `B_S` | An added continuous eight-packet burst in `TbNocBasic.bsv` | Payload bytes divided by `last collection - first collection + 1`. |
| `B_R` | `TbNocRouterPerf.bsv` | All five outputs of one router, over the steady-state window. |
| `B_N` | `TbNocNetworkPerf.bsv` | All sixteen local outputs, over the steady-state window. |

`NocMetrics.bsv` contains the small latency/stream observers, rate formatting,
and shared packet-pattern helpers. Observer methods write event wires; their
recording rules do not add readiness conditions to the DUT methods.
The extra `router_latency` line is a diagnostic for a standalone router, not
the assignment's end-to-end `L0`.

The original functional tests remain in place. The added stream source is a
separate rule that attempts a put every cycle, avoiding FSM loop overhead.
It uses the original packet checker. `B_R` uses saturated synthetic input
streams with a distinct output for each input; it measures router capacity.
The end-to-end `B_N` workload enforces A4 for each PE and checks the complete
packet and per-source order before allowing that source's next message.
Its seeded xorshift generator selects a rank among the other fifteen nodes.
Collectors/checkers/counters are independent per destination, permitting
multiple successful gets in the same cycle.

## Run

Run in the environment where `bsc` is installed, including your Docker
container if that is where you normally compile:

```bash
python3 run_metrics.py --label base_d4
```

To pass an explicit compiler option:

```bash
python3 run_metrics.py --label base_d4 --bsc-flag=-aggressive-conditions
```

For individual experiments and longer windows:

```bash
python3 run_metrics.py --tests router-perf network-perf \
    --warmup 2000 --cycles 20000 --seed 7 --label base_d4
```

Use `--bsc /absolute/path/to/bsc` if it is outside your PATH. With no extra
flags, the runner uses the assignment's default Verilog compilation options.
The warm-up, window, and seed overrides use preprocessor definitions from
`NocMetrics.bsv`; your source files are not rewritten.

Each run gets a new directory under `build-metrics/`, containing a snapshot
of the BSV sources, generated RTL, compiler/simulation logs, `manifest.json`,
and `metrics.csv`. The manifest records source hashes and compiler options.
Only measurements from passing, fully drained benchmarks enter the CSV.
Failures are detected from both process status and `FAIL` output, since
Bluesim can return exit status zero after a failing `$finish`.

Rates printed in the simulation have three truncated decimal places and
include their exact byte/cycle counts. The CSV recomputes rates from those
exact counts. `B_R` and `B_N` count only the half-open cycle interval
`[warmup, warmup + window)`, then stop starting traffic and verify drainage;
warm-up and drain cycles are excluded from their denominators.

Repeat runs with longer windows and additional seeds before calling a rate
steady state. Keep the same workloads/window settings when comparing designs.
Do not treat a timed-out workload as a valid bandwidth result.

## Physical units

After obtaining an achieved clock period from your physical flow, optionally
pass `--clock-period-ns PERIOD`. The CSV adds `latency_ns` and
`bytes_per_second`; without that argument it reports cycle-based quantities
only. No clock frequency or synthesis area is guessed by the testbenches.

## Baseline compatibility

A clean run of the current depth-four router with local BSC 2025.07 and no
`-aggressive-conditions` stalls in the original first single-packet test.
The metric instrumentation does not repair that implementation issue. An
explicit flag run can characterize the current design, but passing default
submission commands remains a separate requirement before reporting a
configuration as valid.

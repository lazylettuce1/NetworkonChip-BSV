# CS6230 A2 — EE23B141

4×4 mesh with XY routing, depth-2 registered inputs, and one masked round-robin
arbiter per output. `NocTypes.bsv` is the unchanged assignment interface.
Tested with BSC 2025.07; run the commands from this directory with `bsc` on PATH.

## Configurations

| Design ID | Configuration | BSC define | Closing clock |
|---|---|---|---|
| 0 | Baseline: ordinary depth-2 outputs | `-D NOC_BUFFERED_OUTPUTS` | 0.60 ns |
| 1 | Bypass: depth-2 outputs (code default) | none | 0.75 ns |
| 2 | Bypass: depth-1 outputs | `-D NOC_BYPASS_DEPTH1` | 0.75 ns |

**Recommended for evaluation: design 2**, highest clock-scaled bandwidth/area.
Design 0 has the highest absolute network bandwidth. Numbered
`design_<ID>_qor.rpt`, `design_<ID>_dc.tcl`, and `design_<ID>_noc.sdc` match this table.

## Build and test

Select `design=0`, `1`, or `2`. Separate simulation/Verilog directories prevent
mixing backends or configurations. No `-aggressive-conditions` is required.

```bash
bash <<'SH'
set -e
design=2
seed=1
case "$design" in
  0) flags=(-D NOC_BUFFERED_OUTPUTS) ;;
  1) flags=() ;;
  2) flags=(-D NOC_BYPASS_DEPTH1) ;;
esac
b="build/design_${design}_seed_${seed}"
mkdir -p "$b/sim" "$b/rtl"
for tb in TbNocRouter TbNocBuffer TbNocBasic TbNocRouterPerf TbNocNetworkPerf; do
  bsc "${flags[@]}" -D "METRIC_SEED=$seed" -u -sim \
      -bdir "$b/sim" -simdir "$b/sim" -info-dir "$b/sim" -g "mk$tb" "$tb.bsv"
  bsc -sim -bdir "$b/sim" -simdir "$b/sim" -e "mk$tb" -o "$b/sim/$tb"
  "$b/sim/$tb"
done
bsc "${flags[@]}" -u -verilog -bdir "$b/rtl" -vdir "$b/rtl" \
    -info-dir "$b/rtl" -g mkNoc Noc.bsv
SH
```

| Testbench | Checks / metrics |
|---|---|
| `TbNocRouter` | Five routes, XY priority, complete-packet comparison |
| `TbNocBuffer` | Output latency, backpressure, independent progress, ordered drain |
| `TbNocBasic` | All node pairs, messages, destination stalls; **L0, BS** |
| `TbNocRouterPerf` | Saturated router, packet/order checks; **BR** |
| `TbNocNetworkPerf` | All-node random messages, packet/order checks, full drain; **BN** |

Passing runs print `PASS` or `ALL TESTS PASSED`; any `FAIL` invalidates the result.
BR/BN use 1,000 warm-up and 10,000 measurement cycles. Repeat with `seed=2` and
`seed=3`; the report uses mean BN across seeds 1–3. Bandwidth counts payload bytes.
`NocMetrics.bsv` supplies the shared testbench helpers.

## Synthesis

After the Verilog build, select the same design/seed below. Run on the EDA host
with Design Compiler and the SAED14 libraries available; library paths are in Tcl.
The included `FIFO2.v` and `RevertReg.v` are matching BSC primitives.

```bash
design=2
seed=1
b="build/design_${design}_seed_${seed}"
r="synth/design_${design}"
mkdir -p "$r/rtl" "$r/syn/scripts" "$r/syn/work"
cp "$b/rtl/"*.v FIFO2.v RevertReg.v "$r/rtl/"
cp "design_${design}_dc.tcl" "$r/syn/scripts/dc.tcl"
cp "design_${design}_noc.sdc" "$r/syn/scripts/noc.sdc"
(cd "$r/syn/work" && dc_shell -f ../scripts/dc.tcl)
```

Reports are written to `synth/design_<ID>/syn/reports/`. Constraints use the
SAED14 RVT slow corner (0.72 V, 125°C) and I/O delays of 40% of the clock period.
Exit the DC prompt after reports finish. Synthesis consumes `.v` files;
`.bo`/`.ba` files are compiler/simulation artifacts.

## Submission

Add `bsv_results.pdf` and `pd_results.pdf`, then package the numbered QoR reports
under `pd_reports/` as specified. This excludes generated builds:

```bash
mkdir -p pd_reports
cp design_*_qor.rpt pd_reports/
zip -r EE23B141_assign2.zip *.bsv README.md *.v \
    design_*_dc.tcl design_*_noc.sdc pd_reports bsv_results.pdf pd_results.pdf
```

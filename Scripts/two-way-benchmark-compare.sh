#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  Scripts/two-way-benchmark-compare.sh [legacy_root]

Defaults:
  legacy_root=/Users/barut/OmniBenchmark/v0.3.4
  rewrite_root=<script repo root>
  OMNI_BENCH_RUNS=3
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REWRITE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LEGACY_ROOT="${1:-/Users/barut/OmniBenchmark/v0.3.4}"
RUNS="${OMNI_BENCH_RUNS:-3}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${REWRITE_ROOT}/dist/benchmarks/two-way/${STAMP}"

mkdir -p "${OUT_DIR}"

if [[ ! -d "${LEGACY_ROOT}" ]]; then
    echo "Legacy root does not exist: ${LEGACY_ROOT}" >&2
    exit 1
fi

if [[ ! -e "${LEGACY_ROOT}/Frameworks" && -d "${REWRITE_ROOT}/Frameworks" ]]; then
    ln -s "${REWRITE_ROOT}/Frameworks" "${LEGACY_ROOT}/Frameworks"
fi

run_release_tests() {
    local candidate="$1"
    local root="$2"
    local log_path="${OUT_DIR}/${candidate}/release-tests.log"
    mkdir -p "$(dirname "${log_path}")"

    echo "==> ${candidate}: swift test -c release"
    (
        cd "${root}"
        swift test -c release
    ) | tee "${log_path}"
}

run_benchmark_family() {
    local candidate="$1"
    local root="$2"
    local family="$3"
    local script_name="$4"
    local latest_report_name="$5"
    local candidate_dir="${OUT_DIR}/${candidate}"
    mkdir -p "${candidate_dir}"

    for run in $(seq 1 "${RUNS}"); do
        echo "==> ${candidate}: ${family} run ${run}/${RUNS}"
        (
            cd "${root}"
            "./Scripts/${script_name}"
        ) | tee "${candidate_dir}/${family}-run${run}.log"

        cp "${root}/dist/benchmarks/${latest_report_name}" \
            "${candidate_dir}/${family}-run${run}.json"
    done
}

run_release_tests "rewrite" "${REWRITE_ROOT}"
run_release_tests "legacy" "${LEGACY_ROOT}"

run_benchmark_family "rewrite" "${REWRITE_ROOT}" "phase0" "niri-phase0-benchmark.sh" "niri-phase0-latest.json"
run_benchmark_family "legacy" "${LEGACY_ROOT}" "phase0" "niri-phase0-benchmark.sh" "niri-phase0-latest.json"
run_benchmark_family "rewrite" "${REWRITE_ROOT}" "runtime" "niri-runtime-benchmark.sh" "niri-runtime-latest.json"
run_benchmark_family "legacy" "${LEGACY_ROOT}" "runtime" "niri-runtime-benchmark.sh" "niri-runtime-latest.json"

python3 - "${REWRITE_ROOT}" "${LEGACY_ROOT}" "${OUT_DIR}" "${RUNS}" <<'PY'
import json
import pathlib
import statistics
import subprocess
import sys

rewrite_root = pathlib.Path(sys.argv[1])
legacy_root = pathlib.Path(sys.argv[2])
out_dir = pathlib.Path(sys.argv[3])
runs = int(sys.argv[4])


def git_value(root: pathlib.Path, *args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        return "unknown"


def load_report(candidate: str, family: str, run: int) -> dict:
    path = out_dir / candidate / f"{family}-run{run}.json"
    with path.open() as handle:
        return json.load(handle)


def aggregate_family(candidate: str, family: str) -> dict:
    reports = [load_report(candidate, family, run) for run in range(1, runs + 1)]
    metric_names = sorted(reports[0]["metrics"].keys())
    aggregated = {}
    for metric in metric_names:
        values = {field: [] for field in ("count", "minMs", "meanMs", "p50Ms", "p95Ms", "p99Ms", "maxMs")}
        for report in reports:
            stats = report["metrics"][metric]
            for field in values:
                values[field].append(stats[field])
        aggregated[metric] = {
            field: statistics.median(series) for field, series in values.items()
        }
    return {
        "scenarioName": reports[0]["scenarioName"],
        "schemaVersion": reports[0]["schemaVersion"],
        "metrics": aggregated,
    }


summary = {
    "rewrite": {
        "root": str(rewrite_root),
        "commit": git_value(rewrite_root, "rev-parse", "HEAD"),
        "describe": git_value(rewrite_root, "describe", "--tags", "--always", "--dirty"),
    },
    "legacy": {
        "root": str(legacy_root),
        "commit": git_value(legacy_root, "rev-parse", "HEAD"),
        "describe": git_value(legacy_root, "describe", "--tags", "--always", "--dirty"),
    },
    "families": {
        "phase0": {
            "rewrite": aggregate_family("rewrite", "phase0"),
            "legacy": aggregate_family("legacy", "phase0"),
        },
        "runtime": {
            "rewrite": aggregate_family("rewrite", "runtime"),
            "legacy": aggregate_family("legacy", "runtime"),
        },
    },
}

(out_dir / "comparison.json").write_text(json.dumps(summary, indent=2, sort_keys=True))

lines = []
lines.append("# Two-Way Benchmark Comparison")
lines.append("")
lines.append("| Candidate | Root | Commit | Describe |")
lines.append("| --- | --- | --- | --- |")
for key in ("rewrite", "legacy"):
    item = summary[key]
    lines.append(f"| {key} | `{item['root']}` | `{item['commit'][:12]}` | `{item['describe']}` |")
lines.append("")

for family in ("phase0", "runtime"):
    family_summary = summary["families"][family]
    lines.append(f"## {family}")
    lines.append("")
    lines.append(
        f"Scenario `{family_summary['rewrite']['scenarioName']}` "
        f"(schema v{family_summary['rewrite']['schemaVersion']}, median of {runs} runs)"
    )
    lines.append("")
    lines.append("| Metric | Rewrite mean | Rewrite p95 | Rewrite p99 | Legacy mean | Legacy p95 | Legacy p99 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    common_metrics = sorted(
        set(family_summary["rewrite"]["metrics"].keys()) &
        set(family_summary["legacy"]["metrics"].keys())
    )
    for metric in common_metrics:
        rewrite_stats = family_summary["rewrite"]["metrics"][metric]
        legacy_stats = family_summary["legacy"]["metrics"][metric]
        lines.append(
            f"| {metric} | "
            f"{rewrite_stats['meanMs']:.6f} | {rewrite_stats['p95Ms']:.6f} | {rewrite_stats['p99Ms']:.6f} | "
            f"{legacy_stats['meanMs']:.6f} | {legacy_stats['p95Ms']:.6f} | {legacy_stats['p99Ms']:.6f} |"
        )
    lines.append("")

(out_dir / "comparison.md").write_text("\n".join(lines) + "\n")
print(f"Wrote {out_dir / 'comparison.json'}")
print(f"Wrote {out_dir / 'comparison.md'}")
PY

echo "==> Two-way comparison bundle: ${OUT_DIR}"

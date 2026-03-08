#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  Scripts/niri-runtime-benchmark.sh [--update-baseline]
EOF
}

UPDATE_BASELINE=false

for arg in "$@"; do
    case "$arg" in
        --update-baseline)
            UPDATE_BASELINE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LATEST_REPORT="${REPO_ROOT}/dist/benchmarks/niri-runtime-latest.json"
BASELINE_REPORT="${REPO_ROOT}/benchmarks/niri/runtime-baseline.json"

mkdir -p "$(dirname "${LATEST_REPORT}")"

echo "==> Running ZigNiri runtime benchmark tests (release)"
(
    cd "${REPO_ROOT}"
    OMNI_RUNTIME_BENCH=1 \
    OMNI_RUNTIME_REPORT_PATH="${LATEST_REPORT}" \
    swift test -c release --filter ZigNiriRuntimeBenchmarkTests
)

if [[ ! -f "${LATEST_REPORT}" ]]; then
    echo "Expected report was not written: ${LATEST_REPORT}" >&2
    exit 1
fi

if [[ "${UPDATE_BASELINE}" == "true" ]]; then
    mkdir -p "$(dirname "${BASELINE_REPORT}")"
    cp "${LATEST_REPORT}" "${BASELINE_REPORT}"
    echo "==> Baseline updated: ${BASELINE_REPORT}"
fi

echo "==> Latest runtime benchmark report: ${LATEST_REPORT}"

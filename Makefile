.PHONY: format lint lint-fix check zig-build niri-phase0-perf-gate niri-runtime-benchmark niri-runtime-perf-gate two-way-benchmark-compare

format:
	swiftformat .

lint:
	swiftlint lint

lint-fix:
	swiftlint lint --fix

check: lint

# Build the Zig static library used by Swift.
# Default output is universal (arm64 + x86_64).
zig-build:
	zig build omni-layout --prefix .build

niri-phase0-perf-gate:
	./Scripts/niri-phase0-perf-gate.sh

niri-runtime-benchmark:
	./Scripts/niri-runtime-benchmark.sh

niri-runtime-perf-gate:
	./Scripts/niri-runtime-perf-gate.sh

two-way-benchmark-compare:
	./Scripts/two-way-benchmark-compare.sh

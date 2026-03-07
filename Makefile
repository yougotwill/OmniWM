.PHONY: format lint lint-fix check zig-build

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

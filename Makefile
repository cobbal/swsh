build:
	xcrun --toolchain "Swift Development Snapshot" swift build

test:
	xcrun --toolchain "Swift Development Snapshot" swift test

docs:
	rm -rf docs
	jazzy --module swsh

.PHONY: build test docs

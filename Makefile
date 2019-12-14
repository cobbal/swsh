build:
	xcrun --toolchain "Swift Development Snapshot" swift build

test:
	xcrun --toolchain "Swift Development Snapshot" swift test

docs:
	jazzy --module swsh

.PHONY: build test docs

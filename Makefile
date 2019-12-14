build:
	xcrun --toolchain "Swift Development Snapshot" swift build

test:
	xcrun --toolchain "Swift Development Snapshot" swift test

docs:
	jazzy --clean --hide-documentation-coverage --module swsh

.PHONY: build test docs

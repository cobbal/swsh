build:
	xcrun --toolchain "Swift Development Snapshot" swift build

test:
	xcrun --toolchain "Swift Development Snapshot" swift test

.PHONY: build test

build:
	xcrun swift build

test: build
	xcrun swift test

docs:
	jazzy --clean --module swsh

.PHONY: build test docs

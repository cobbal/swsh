build:
	swift build --enable-test-discovery

test: build
	swift test --enable-test-discovery --enable-code-coverage

docs:
	jazzy --clean --module swsh

coverage.lcov:
	xcrun llvm-cov export \
		-instr-profile=$$(echo .build/debug/codecov/*.profdata) \
		-object=$$(find .build/debug/*.xctest/Contents/MacOS -type f -depth 1) -format=lcov \
		> coverage.lcov

.PHONY: build test docs

build:
	swift build --enable-test-discovery

test: build
	swift test --enable-test-discovery --enable-code-coverage

docs:
	bundle exec jazzy --clean --module swsh
	mkdir -p docs/docs; cp docs/badge.svg docs/docs/

coverage.lcov:
	xcrun llvm-cov export \
		-instr-profile=$$(echo .build/debug/codecov/*.profdata) \
		-object=$$(find .build/debug/*.xctest/Contents/MacOS -type f -depth 1) -format=lcov \
		> coverage.lcov

.PHONY: build test docs

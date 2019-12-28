build:
	swift build --enable-test-discovery

test: build
	swift test --enable-test-discovery --enable-code-coverage

docs:
	bundle exec jazzy --clean \
	    --module swsh \
	    --github_url https://github.com/cobbal/swsh

lint:
	swiftlint lint --strict --quiet

lint-fix:
	swiftlint autocorrect

coverage.lcov:
	xcrun llvm-cov export \
		-instr-profile=$$(echo .build/debug/codecov/*.profdata) \
		-object=$$(find .build/debug/*.xctest/Contents/MacOS -type f -depth 1) -format=lcov \
		> coverage.lcov

.PHONY: build test docs lint

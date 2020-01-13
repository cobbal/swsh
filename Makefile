build:
	swift build

test: build
	swift test --enable-code-coverage

test-and-generate-linux-tests: build
	swift test --enable-code-coverage --generate-linuxmain

docs: docs/swsh-master

docs/swsh-%: docs-phony
	bundle exec jazzy --clean \
	  --module-version $* \
	  --output $@ \
	  --docset-path ../../$@.docset

swsh-%.tar.xz: docs/swsh-%
	tar cJf $@ -C docs swsh-$*

lint:
	swiftlint lint --strict --quiet

lint-fix:
	swiftlint autocorrect

coverage.lcov:
	xcrun llvm-cov export \
		-instr-profile=$$(echo .build/debug/codecov/*.profdata) \
		-object=$$(find .build/debug/*.xctest/Contents/MacOS -type f -depth 1) -format=lcov \
		> coverage.lcov

.PHONY: build test lint docs-phony

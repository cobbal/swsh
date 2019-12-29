build:
	swift build --enable-test-discovery

test: build
	swift test --enable-test-discovery --enable-code-coverage

docs: docs/swsh-master

docs/swsh-%: docs-phony
	bundle exec jazzy --clean \
	  --module-version $* \
	  --output $@ \
	  --docset-path ../../$@.docset

swist-%.tar.xz: docs/swsh-%
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

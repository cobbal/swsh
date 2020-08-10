# [2.0.0](https://github.com/cobbal/swsh/compare/v1.0.1...v2.0.0) (2020-08-10)


### Features

* fd duplication and more general output/error combining ([1667abd](https://github.com/cobbal/swsh/commit/1667abd0bf7b9c84c0d3c0835a5abdd7f590c4c5))
* rework FD mapping systems ([5becc68](https://github.com/cobbal/swsh/commit/5becc68299b150069c007ca62c9f9c8dcb15869f))


### BREAKING CHANGES

* Traditional, imperative file descriptor remapping has
    been removed in favor of a more functional mapping of what the child
    process will see. dup calls are now synthesized to get the right FDs
    in the right place.

    Hopefully, this will be more composable.

    Also, joinErr parameters have been removed in favor of the
    `combineError` property.

## [1.0.1](https://github.com/cobbal/swsh/compare/v1.0.0...v1.0.1) (2020-07-20)


### Bug Fixes

* default kill signal should be TERM ([639a7af](https://github.com/cobbal/swsh/commit/639a7af5161297bb4958f0e8d2974d4f712cc33e))

# [1.0.0](https://github.com/cobbal/swsh/compare/v0.2.0...v1.0.0) (2020-07-16)


### Features

* killing processes ([a787f6a](https://github.com/cobbal/swsh/commit/a787f6af1ac64ecdce8ab62a35b6bbb73f13e4ae))


### BREAKING CHANGES

* `runJson` has been renamed to `runJSON`

# [0.2.0](https://github.com/cobbal/swsh/compare/v0.1.0...v0.2.0) (2020-02-07)


### Bug Fixes

* docs not building in release ([5936876](https://github.com/cobbal/swsh/commit/5936876fec4ff13c707024650ada9854998c7823))
* make API public instead of internal ([6416599](https://github.com/cobbal/swsh/commit/64165991dffe3f944b0a8c8916835b42cb78ceba))
* release script ([#9](https://github.com/cobbal/swsh/issues/9)) ([5387ec7](https://github.com/cobbal/swsh/commit/5387ec78a28c98c696c391fb697b55d48a99864c))
* report correct exit code ([28ca42b](https://github.com/cobbal/swsh/commit/28ca42bbb0fb3720848b3f9f3b32df581d42b3d6))


### Features

* Add linux support ([#7](https://github.com/cobbal/swsh/issues/7)) ([15f7339](https://github.com/cobbal/swsh/commit/15f733951456ee45d4b066861a9b0b6444f2fef2))

# [0.2.0](https://github.com/cobbal/swsh/compare/v0.1.0...v0.2.0) (2020-02-07)


### Bug Fixes

* docs not building in release ([5936876](https://github.com/cobbal/swsh/commit/5936876fec4ff13c707024650ada9854998c7823))
* make API public instead of internal ([6416599](https://github.com/cobbal/swsh/commit/64165991dffe3f944b0a8c8916835b42cb78ceba))
* report correct exit code ([28ca42b](https://github.com/cobbal/swsh/commit/28ca42bbb0fb3720848b3f9f3b32df581d42b3d6))


### Features

* Add linux support ([#7](https://github.com/cobbal/swsh/issues/7)) ([15f7339](https://github.com/cobbal/swsh/commit/15f733951456ee45d4b066861a9b0b6444f2fef2))

# [0.2.0](https://github.com/cobbal/swsh/compare/v0.1.0...v0.2.0) (2020-01-13)


### Bug Fixes

* docs not building in release ([5936876](https://github.com/cobbal/swsh/commit/5936876fec4ff13c707024650ada9854998c7823))
* make API public instead of internal ([6416599](https://github.com/cobbal/swsh/commit/64165991dffe3f944b0a8c8916835b42cb78ceba))
* report correct exit code ([28ca42b](https://github.com/cobbal/swsh/commit/28ca42bbb0fb3720848b3f9f3b32df581d42b3d6))


### Features

* Add linux support ([#7](https://github.com/cobbal/swsh/issues/7)) ([15f7339](https://github.com/cobbal/swsh/commit/15f733951456ee45d4b066861a9b0b6444f2fef2))

## [0.1.1](https://github.com/cobbal/swsh/compare/v0.1.0...v0.1.1) (2019-12-30)


### Bug Fixes

* docs not building in release ([5936876](https://github.com/cobbal/swsh/commit/5936876fec4ff13c707024650ada9854998c7823))
* make API public instead of internal ([6416599](https://github.com/cobbal/swsh/commit/64165991dffe3f944b0a8c8916835b42cb78ceba))
* report correct exit code ([28ca42b](https://github.com/cobbal/swsh/commit/28ca42bbb0fb3720848b3f9f3b32df581d42b3d6))

# [0.1.0](https://github.com/cobbal/swsh/compare/v0.0.2...v0.1.0) (2019-12-28)


### Features

* initial release ([b5cc527](https://github.com/cobbal/swsh/commit/b5cc5276cbcf59950de0bfb5a96be22d71b3ce14))

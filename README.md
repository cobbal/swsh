# swsh

[![](https://github.com/cobbal/swsh/workflows/tests/badge.svg?branch=master)][3] [![](docs/badge.svg)][2] [![](https://codecov.io/gh/cobbal/swsh/branch/master/graph/badge.svg)][4]

A shell-scripting library for Swift, inspired by [scsh][2].

swsh makes writing shell scripts more fun by exchanging bash (or similar) for a better thought-out language like Swift. In the process,
a small amount of conciseness is traded for better quoting, error handling, and access to libraries.

Some poorly thought out examples:
```swift
import swsh

try! (cmd("ls") | cmd("sort", "-n")).runLines()
// -> ["1.sh", "9.sh", "10.sh"]

["hello", "world", ""].map { cmd("test", "-z", $0).runBool() }
// -> [false, false, true]

try! (cmd("false") | cmd("cat")).run()
// Fatal error: 'try!' expression unexpectedly raised an error: command "false" failed with exit code 256
```

[Full documentation][2]

[1]: https://scsh.net/
[2]: https://cobbal.github.io/swsh/
[3]: https://github.com/cobbal/swsh/actions?query=workflow%3Atests+branch%3Amaster
[4]: https://codecov.io/gh/cobbal/swsh

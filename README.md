# swsh

[![CI tests][ci-badge]][ci-tests]
[![documentation][docs-badge]][docs]
[![coverage][cov-badge]][cov]

A shell-scripting library for Swift, inspired by [scsh][scsh].

swsh makes writing shell scripts more fun by exchanging bash (or similar) for a better thought-out language like Swift. In the process,
a small amount of conciseness is traded for better quoting, error handling, and access to libraries.

Some poorly thought out examples:
```swift
import swsh

let rot13 = cmd("tr", "a-z", "n-za-m")
try! rot13.input("secret message").runString()
// -> "frperg zrffntr"

try! (rot13.input("secret") | rot13).runString()
// -> "secret"

try! (cmd("ls") | cmd("sort", "-n")).runLines()
// -> ["1.sh", "9.sh", "10.sh"]

["hello", "world", ""].map { cmd("test", "-z", $0).runBool() }
// -> [false, false, true]

try! (cmd("false") | cmd("cat")).run()
// Fatal error: 'try!' expression unexpectedly raised an error: command "false" failed with exit code 256
```

[Full documentation][docs]

[ci-tests]: https://github.com/cobbal/swsh/actions?query=workflow%3Atests+branch%3Amaster
[docs]: https://cobbal.github.io/swsh/
[cov]: https://codecov.io/gh/cobbal/swsh
[scsh]: https://scsh.net/

[ci-badge]: https://github.com/cobbal/swsh/workflows/tests/badge.svg
[docs-badge]: https://cobbal.github.io/swsh/badge.svg
[cov-badge]: https://codecov.io/gh/cobbal/swsh/branch/master/graph/badge.svg

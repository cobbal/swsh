import swsh

ExternalCommand.verbose = true

enum Error: Swift.Error {
    case wrongAnswer
}

print("Running command...")
do {
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").run()
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").output(overwritingFile: "foo.txt").run()
    // guard try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").runString() == "hiya" else { throw Error.wrongAnswer }
    print(try cmd("echo", "hi").runString())
    // try cmd("tr", "a-z", "n-za-m").input("secret message").run()
    // print(try cmd("tr", "a-z", "n-za-m").input("secret message").runString())
    // try cmd("tr", "a-z", "n-za-m").runString()
    try! Pipeline(cmd("echo", "foo"), cmd("cat"), cmd("cat")).run()
} catch {
    print("Error running command: \(error)")
}
print("Finished running command.")

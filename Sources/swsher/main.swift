import swsh

ExternalCommand.verbose = true

enum Error: Swift.Error {
    case wrongAnswer
}

print("Running command...")
do {
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").run()
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").output(overwritingFile: "foo.txt").run()
    guard try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").runString() == "hiya" else { throw Error.wrongAnswer }
} catch {
    print("Error running command: \(error)")
}
print("Finished running command.")

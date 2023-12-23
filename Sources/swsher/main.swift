import swsh

ExternalCommand.verbose = true

enum Error: Swift.Error {
    case wrongAnswer
    case couldNotDelete
}

print("Running commands...")
do {
    try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").run()
    try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").output(overwritingFile: "foo.txt").run()
    guard try cmd("C:\\Program Files\\Git\\usr\\bin\\cat.exe", "foo.txt").runString() == "hiya" else { throw Error.wrongAnswer }
    guard try cmd("C:\\Program Files\\Git\\usr\\bin\\rm.exe", "foo.txt").runBool() else { throw Error.couldNotDelete }
    guard try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").runString() == "hiya" else { throw Error.wrongAnswer }
    guard try cmd("echo", "hi").runString() == "hi" else { throw Error.wrongAnswer }
    // guard try cmd("tr", "a-z", "n-za-m").input("secret message").runString() == "frperg zrffntr" else { throw Error.wrongAnswer }
    guard try Pipeline(cmd("echo", "secret message"), cmd("tr", "a-z", "n-za-m")).runString() == "frperg zrffntr" else { throw Error.wrongAnswer }
} catch {
    fatalError("Error running commands: \(error)")
}
print("Finished running commands successfully.")

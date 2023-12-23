import swsh

ExternalCommand.verbose = true
ExternalCommand.supplementaryPath = ";C:\\Program Files\\Git\\usr\\bin"

enum Error: Swift.Error {
    case wrongAnswer
    case couldNotDelete
}

print("Running commands...")
do {
    try cmd("echo", "hiya").run()
    try cmd("echo", "hiya").output(overwritingFile: "foo.txt").run()
    guard try cmd("cat", "foo.txt").runString() == "hiya" else { throw Error.wrongAnswer }
    guard try cmd("rm", "foo.txt").runBool() else { throw Error.couldNotDelete }
    guard try cmd("echo", "hiya").runString() == "hiya" else { throw Error.wrongAnswer }
    guard try cmd("echo", "hi").runString() == "hi" else { throw Error.wrongAnswer }
    guard try cmd("tr", "a-z", "n-za-m").input("secret message").runString() == "frperg zrffntr" else { throw Error.wrongAnswer }
    guard try Pipeline(cmd("echo", "secret message"), cmd("cat"), cmd("tr", "a-z", "n-za-m")).runString() == "frperg zrffntr" else { throw Error.wrongAnswer }
} catch {
    fatalError("Error running commands: \(error)")
}
print("Finished running commands successfully.")

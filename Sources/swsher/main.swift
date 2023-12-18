import swsh

ExternalCommand.verbose = true

print("Running command...")
do {
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").run()
    try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").output(overwritingFile: "foo.txt").run()
} catch {
    print("Error running command: \(error)")
}
print("Finished running command.")

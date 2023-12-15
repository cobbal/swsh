import swsh

print("Running command...")
do {
    // try cmd("C:\\Program Files\\Git\\usr\\bin\\echo.exe", "hiya").run()
    try cmd("echo", "hiya").run()
} catch {
    print("Error running command: \(error)")
}
print("Finished running command.")

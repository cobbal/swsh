#if os(Windows)

// "_getpid" returns int, so I guess that's what pid_t should be??
// https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/getpid
public typealias pid_t = Int
public let SIGKILL: Int32 = 9
public let SIGTERM: Int32 = 15
public let SIGSTOP: Int32 = 19
public let SIGCONT: Int32 = 18
#endif

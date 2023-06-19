import Foundation
import WinSDK

// Adapted from libuv:
// https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c

func spawn(
    command: String,
    arguments: [String],
    env: [String: String],
    fdMap: [Int: Int],
    pathResolve: Bool
) -> Int? {
    guard let command = command.withCString(encodedAs: UTF16.self, _wcsdup) else {
        return nil
    }
    defer { free(command) }

    var startupInfo = STARTUPINFOW()
    startupInfo.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startupInfo.dwFlags = STARTF_USESTDHANDLES

    let err = CreateProcessW(
        command,
        lpCommandLine: LPWSTR!,
        lpProcessAttributes: LPSECURITY_ATTRIBUTES!,
        lpThreadAttributes: LPSECURITY_ATTRIBUTES!,
        bInheritHandles: Bool,
        dwCreationFlags: DWORD,
        lpEnvironment: LPVOID!,
        lpCurrentDirectory: LPCWSTR!,
        &startupInfo,
        lpProcessInformation: LPPROCESS_INFORMATION!
    )
}
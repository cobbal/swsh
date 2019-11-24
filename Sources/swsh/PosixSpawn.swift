//
//  File.swift
//  
//
//  Created by Andrew Cobb on 11/10/19.
//

import Foundation

#if os(OSX)
import Darwin.C
#else
import Glibc
#warning("TODO: never been tested, probably broken")
#endif

struct SpawnError: Error {
    let errnum: Int32

    var localizedDescription: String {
        String(cString: strerror(errnum))
    }
}

/// low level code to spawn a process
/// fdMap is a list of file descriptor remappings, src -> dst (can be equal)
/// Note: all unmapped descriptors will be closed
/// Returns pid of spawned process

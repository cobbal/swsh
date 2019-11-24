//
//  File.swift
//  
//
//  Created by Andrew Cobb on 11/11/19.
//

import Foundation

public struct JobControl {
    static let shared = JobControl()

    // never block this
    static let jobQueue = DispatchQueue(label: "swsh.JobControl.jobQueue")

    private init() {
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: JobControl.jobQueue)
        source.setEventHandler {
            print("TERM")
            exit(0)
        }
        source.activate()
    }
}

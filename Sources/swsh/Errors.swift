//
//  File.swift
//  
//
//  Created by Andrew Cobb on 11/8/19.
//

import Foundation

public struct InvalidString: Error {
    let data: Data
    let encoding: String.Encoding
}

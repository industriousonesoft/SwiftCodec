//
//  Utilities.swift
//  CodecDemo
//
//  Created by Mark Cao on 2020/4/15.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

class Utilities : NSObject {
    
    var machTimebaseInfo: mach_timebase_info_t = UnsafeMutablePointer<mach_timebase_info>.allocate(capacity: 1)
    
    static let shared = Utilities()
    
    private override init() {
        super.init()
        mach_timebase_info(self.machTimebaseInfo)
    }
    
    override
    func copy() -> Any {
        return self
    }
    
    override
    func mutableCopy() -> Any {
        return self
    }
    
    func machAbsoluteToSeconds(machAbsolute: UInt64) -> Double {
        let nanos = Double(machAbsolute * UInt64(machTimebaseInfo.pointee.numer)) / Double(machTimebaseInfo.pointee.denom)
        return nanos / 1.0e9
    }
    
}

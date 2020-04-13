//
//  NSError+Extend.swift
//  FFmpegWrapper
//
//  Created by caowanping on 2020/1/14.
//  Copyright © 2020 zenet. All rights reserved.
//

import Foundation

extension NSError {
    
    static func error(_ domain: String, code: Int, reason: String) -> NSError? {
        return NSError.init(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey : reason])
    }
    
    static func error(_ domain: String, reason: String) -> NSError? {
        return NSError.init(domain: domain, code: -1, userInfo: [NSLocalizedDescriptionKey : reason])
    }
}

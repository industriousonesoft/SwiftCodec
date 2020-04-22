//
//  DataCacher.swift
//  TryVNCDemo-Telegraph
//
//  Created by caowanping on 2019/12/17.
//  Copyright © 2019 zdnet. All rights reserved.
//

import Foundation

class DataCacher {
    
    private var fileHandle: FileHandle?
 
}

extension DataCacher {
    func reset(fileName: String) {
        self.fileHandle?.closeFile()
        self.fileHandle = nil
        if let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first {
            let cacheURL = URL.init(fileURLWithPath: cacheDir).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try? FileManager.default.removeItem(at: cacheURL)
            }
            FileManager.default.createFile(atPath: cacheURL.path, contents: nil, attributes: nil)
            print("Cache Path: \(cacheURL.path)")
            self.fileHandle = FileHandle.init(forWritingAtPath: cacheURL.path)
        }
    }
    
    func write(data: Data) {
        self.fileHandle?.seekToEndOfFile()
        self.fileHandle?.write(data)
    }
    
    func close() {
        self.fileHandle?.closeFile()
    }
}

//
//  CircleQueue.swift
//  DesktopCapturer
//
//  Created by Mark Cao on 2020/4/17.
//  Copyright © 2020 zenet. All rights reserved.
//

import Cocoa

let CircleQueueDefaultMaxSize: Int = 5

/// 循环队列
class CircleQueue<T> {
    
    private var data = [T?]()
    
    private var frontIndex = 0
    
    private var rearIndex = 0
    
    private var maxSize: Int
    
    private lazy var queue: DispatchQueue = {
        return DispatchQueue.init(label: "com.zdnet.CircleQueue.quque." + UUID().uuidString)
    }()
    
    init(size: Int) {
        self.maxSize = size
        self.data = [T?](repeating: nil, count: size)
    }
    
    func destroy() {
        self.queue.async { [unowned self] in
            self.data.removeAll()
            self.frontIndex = 0
            self.rearIndex = 0
            self.maxSize = 0
        }
    }
    
    func enqueue(element: T) {
        self.queue.async { [unowned self] in
            self.data[self.rearIndex] = element
            self.rearIndex = (self.rearIndex + 1) % self.maxSize
        }
    }
    
    func dequeue() -> T? {
        var item: T? = nil
        self.queue.sync { [unowned self] in
            item = self.data[frontIndex]
            self.data[frontIndex] = nil
            self.frontIndex = (frontIndex + 1) % maxSize
        }
        return item
    }
    
    func front() -> T? {
        var item: T? = nil
        self.queue.sync { [unowned self] in
            item = self.data[frontIndex]
            self.frontIndex = (frontIndex + 1) % maxSize
        }
        return item
    }

    func reset(forEach body: @escaping (T?) -> Void) {
        self.queue.async { [unowned self] in
            self.frontIndex = 0
            self.rearIndex = 0
            self.data.forEach(body)
        }
    }
}

//
//  AppDelegate.swift
//  CodecDemo
//
//  Created by Mark Cao on 2020/4/15.
//  Copyright © 2020 zenet. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    lazy var ffmpegEncoder: FFmpegEncoder = {
        return FFmpegEncoder.init()
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try self.ffmpegEncoder.open()
            self.ffmpegEncoder.start()
        } catch let err {
            print(err.localizedDescription)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        self.ffmpegEncoder.close()
    }


}

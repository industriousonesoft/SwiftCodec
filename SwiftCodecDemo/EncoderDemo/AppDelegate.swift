//
//  AppDelegate.swift
//  EncoderDemo
//
//  Created by Mark Cao on 2020/4/25.
//  Copyright © 2020 ZDNet. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    private lazy var ffmpegEncoder: FFmpegEncoder = {
        return FFmpegEncoder.init()
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try self.ffmpegEncoder.open()
        } catch let err {
            print(err.localizedDescription)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        self.ffmpegEncoder.close()
    }


}

extension AppDelegate {
    
    @IBAction func start(_ sender: AnyObject) {
        self.ffmpegEncoder.start()
    }
    
    @IBAction func stop(_ sender: AnyObject) {
        self.ffmpegEncoder.stop()
    }
}


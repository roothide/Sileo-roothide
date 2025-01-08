//
//  Download.swift
//  Sileo
//
//  Created by CoolStar on 8/3/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

final class Download {
    var package: Package
    var task: EvanderDownloader?
    var backgroundTask: UIBackgroundTaskIdentifier?
    var progress = CGFloat(0)
    var failureReason: String?
    var totalBytesWritten = Int64(0)
    var totalBytesExpectedToWrite = Int64(0)
    var success = false
    var queued = false
    var completed = false
    var started = false
    var message: String?
    var session: UInt32
    
    init(package: Package, session: UInt32) {
        self.package = package
        self.session = session
    }
    
    func beginBackgroundTask() {
        self.backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
//just let the task pending in background            self.task?.cancel()
            if let backgroundTaskIdentifier = self.backgroundTask {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
            self.backgroundTask = nil
        })
    }
    
    func endBackgroundTask() {
        if let backgroundTaskIdentifier = self.backgroundTask {
            self.backgroundTask = nil
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
    }
}

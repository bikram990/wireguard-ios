// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Cocoa
import os.log

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        launchMainApp()
    }

    func launchMainApp() {
        let appIdInfoDictionaryKey = "com.wireguard.macos.app_id"
        guard let appId = Bundle.main.object(forInfoDictionaryKey: appIdInfoDictionaryKey) as? String else {
            os_log("Cannot obtain app ID from bundle", log: OSLog.default, type: .error)
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: appId).isEmpty else { return }
        var bundleURL = Bundle.main.bundleURL
        // From <path>/WireGuard.app/Contents/Library/LoginItems/WireGuardLaunchAtLoginHelper.app, get <path>/WireGuard.app
        for _ in 0 ..< 4 {
            bundleURL.deleteLastPathComponent()
        }
        NSWorkspace.shared.launchApplication(bundleURL.path)
    }
}

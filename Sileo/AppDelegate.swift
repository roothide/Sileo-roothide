//
//  AppDelegate.swift
//  Sileo
//
//  Created by CoolStar on 8/29/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import UserNotifications
import Evander

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@main
class SileoAppDelegate: UIResponder, UIApplicationDelegate, UITabBarControllerDelegate {
    public var window: UIWindow?
    
    static let presentQueue = DispatchQueue(label: "presentQueue")
    static func presentController(_ controller: UIViewController)
    {
        presentQueue.async {
            var presenting = false
            var presented = false
            
            while !presenting {
                DispatchQueue.main.sync {
                    var vc = UIApplication.shared.keyWindow!.rootViewController!
                    while vc.presentedViewController != nil {
                        vc = vc.presentedViewController!
                        if vc.isBeingDismissed {
                            return
                        }
                    }
                    
                    presenting = true
                    vc.present(controller, animated: true) {
                        presented = true
                    }
                }
                
                if !presenting {
                    usleep(1000*100)
                }
            }

            while !presented {
                usleep(100*1000)
            }
        }
    }
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        NSLog("SileoLog: willFinishLaunchingWithOptions")
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        NSLog("SileoLog: applicationDidBecomeActive")
    }
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        NSLog("SileoLog: applicationDidFinishLaunching")
//uicache redirected
//        EvanderNetworking.CACHE_FORCE = .libraryDirectory // Library/Cache -> /Library ?
//        let prefix = CommandPath.prefix
//        let old = EvanderNetworking._cacheDirectory //but why stil got file:///var/mobile/Library/Caches/Sileo
//        EvanderNetworking._cacheDirectory = URL(fileURLWithPath: prefix + old.path)
//        NSLog("SileoLog: old=\(old), new=\(EvanderNetworking._cacheDirectory)")
//        NSLog("SileoLog: CACHE_FORCE=\(EvanderNetworking.CACHE_FORCE), url=\(FileManager.default.urls(for: EvanderNetworking.CACHE_FORCE, in: .userDomainMask)[0]))")
//        if prefix != "" && old.dirExists {
//            deleteFileAsRoot(old)
//        }
        // Prepare the Evander manifest
        Evander.prepare()
        #if targetEnvironment(macCatalyst)
        _ = MacRootWrapper.shared
        #endif
        SileoThemeManager.shared.updateUserInterface()
        // Begin parsing sources files
        _ = RepoManager.shared
        // Init the local database
        _ = PackageListManager.shared
        _ = DatabaseManager.shared
        _ = DownloadManager.shared
        // Start the language helper for customised localizations
        _ = LanguageHelper.shared

//        UserDefaults.standard.setValue(true, forKey: "uicacheRequired")
        if UserDefaults.standard.bool(forKey: "uicacheRequired") {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: String(localizationKey: "Apply_Changes"), message: String(localizationKey: "Apply_Changes_Confirm"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localizationKey: "After_Install_Relaunch"), style: .destructive, handler: { _ in
                    UserDefaults.standard.setValue(false, forKey: "uicacheRequired")
                    UserDefaults.standard.synchronize()
                    spawnAsRoot(args:[jbroot("/usr/bin/uicache"), "-p", rootfs(Bundle.main.bundlePath)])
                    exit(0)
                }))
                
                SileoAppDelegate.presentController(alert)
            }
        }
        
        guard let tabBarController = self.window?.rootViewController as? UITabBarController else {
            fatalError("Invalid Storyboard")
        }
        tabBarController.delegate = self
        tabBarController.tabBar._blurEnabled = true
        tabBarController.tabBar.tag = WHITE_BLUR_TAG
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
            let updatesPrompt = UserDefaults.standard.bool(forKey: "updatesPrompt")
            if !updatesPrompt {
                if UIApplication.shared.backgroundRefreshStatus == .denied {
                    DispatchQueue.main.async {
                        let title = String(localizationKey: "Background_App_Refresh")
                        let msg = String(localizationKey: "Background_App_Refresh_Message")
                        
                        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                        let okAction = UIAlertAction(title: String(localizationKey: "OK"), style: .cancel) { _ in
                            UserDefaults.standard.set(true, forKey: "updatesPrompt")
                            alert.dismiss(animated: true, completion: nil)
                        }
                        alert.addAction(okAction)
                        SileoAppDelegate.presentController(alert)
                    }
                }
            }
        }
        
        if #available(iOS 13.0, *) {
            
            let bgtaskregisted = BGTaskScheduler.shared.register(forTaskWithIdentifier: "sileo.backgroundrefresh",
                                            using: nil) { [weak self] task in
                self?.handleRefreshTask(task)
            }
            NSLog("SileoLog: bgtaskregisted=\(bgtaskregisted) backgroundRefreshStatus=\(UIApplication.shared.backgroundRefreshStatus)")
            BGTaskScheduler.shared.getPendingTaskRequests { tasks in
                NSLog("SileoLog: pendingTaskRequests=\(tasks)")
            }
        } else {
            UIApplication.shared.setMinimumBackgroundFetchInterval(4 * 3600)
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {_, _ in
            
        }
        
        _ = NotificationCenter.default.addObserver(forName: SileoThemeManager.sileoChangedThemeNotification, object: nil, queue: nil) { _ in
            self.updateTintColor()
            for window in UIApplication.shared.windows {
                for view in window.subviews {
                    view.removeFromSuperview()
                    window.addSubview(view)
                }
            }
        }
        self.updateTintColor()
        
        // Force all view controllers to load now
        for (index, controller) in (tabBarController.viewControllers ?? []).enumerated() {
            _ = controller.view
            if let navController = controller as? UINavigationController {
                _ = navController.viewControllers[0].view
            }
            if index == 4 {
                controller.tabBarItem._setInternalTitle(String(localizationKey: "Search_Page"))
            }
        }
    }
    
    private func backgroundRepoRefreshTask(_ completion: @escaping () -> Void) {
        NSLog("SileoLog: backgroundRepoRefreshTask")
        DispatchQueue.global(qos: .userInitiated).async {
            PackageListManager.shared.initWait()
            let currentUpdates = PackageListManager.shared.availableUpdates().filter({ $0.1?.wantInfo != .hold }).map({ $0.0 })
            let currentPackages = PackageListManager.shared.allPackagesArray
            if currentUpdates.isEmpty { return completion() }
            RepoManager.shared.update(force: false, forceReload: false, isBackground: true) { _, _ in
                let newUpdates = PackageListManager.shared.availableUpdates().filter({ $0.1?.wantInfo != .hold }).map({ $0.0 })
                let newPackages = PackageListManager.shared.allPackagesArray
                if newPackages.isEmpty { return completion() }
                
                let diffUpdates = newUpdates.filter { !currentUpdates.contains($0) }
                if diffUpdates.count > 3 {
                    let content = UNMutableNotificationContent()
                    content.title = String(localizationKey: "Updates Available")
                    content.body = String(format: String(localizationKey: "New updates for %d packages are available"), diffUpdates.count)
                    content.badge = newUpdates.count as NSNumber
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: "org.coolstar.sileo.updates", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                } else {
                    for package in diffUpdates {
                        let content = UNMutableNotificationContent()
                        content.title = String(localizationKey: "New Update")
                        content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                              package.name ?? "",
                                              package.author?.name ?? "",
                                              package.version,
                                              package.sourceRepo?.displayName ?? "")
                        content.badge = newUpdates.count as NSNumber
                        
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                        
                        let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                            content: content,
                                                            trigger: trigger)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                    }
                }

                let diffPackages = newPackages.filter { !currentPackages.contains($0) }
                let wishlist = WishListManager.shared.wishlist
                for package in diffPackages {
                    if wishlist.contains(package.package) {
                        let content = UNMutableNotificationContent()
                        content.title = String(localizationKey: "New Update")
                        content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                              package.name ?? "",
                                              package.author?.name ?? "",
                                              package.version,
                                              package.sourceRepo?.displayName ?? "")
                        content.badge = newUpdates.count as NSNumber
                        
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                        
                        let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                            content: content,
                                                            trigger: trigger)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                    }
                }
                completion()
            }
        }
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        backgroundRepoRefreshTask {
            completionHandler(.newData)
        }
    }
    
    func updateTintColor() {
        var tintColor = UIColor.tintColor
        if UIAccessibility.isInvertColorsEnabled {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            tintColor = UIColor(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 1 - alpha)
        }
        
        if #available(iOS 13, *) {
        } else {
            if UIColor.isDarkModeEnabled {
                UINavigationBar.appearance().barStyle = .blackTranslucent
                UITabBar.appearance().barStyle = .black
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .dark
            } else {
                UINavigationBar.appearance().barStyle = .default
                UITabBar.appearance().barStyle = .default
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .default
            }
        }
        
        UINavigationBar.appearance().tintColor = tintColor
        UIToolbar.appearance().tintColor = tintColor
        UISearchBar.appearance().tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        
        UICollectionView.appearance().tintColor = tintColor
        UITableView.appearance().tintColor = tintColor
        DepictionBaseView.appearance().tintColor = tintColor
        self.window?.tintColor = tintColor
    }
    
    private func aptEncoded(string: String) -> String {
        var encodedString = string.replacingOccurrences(of: "_", with: "%5f")
        encodedString = encodedString.replacingOccurrences(of: ":", with: "%3a")
        return encodedString
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        //NSLog("SileoLog: openurl=\(url) options=\(options)") //crash on NSLog???
        guard let rootVC=self.window?.rootViewController else {
            return true
        }
        if let vc=rootVC.presentedViewController {
            NSLog("SileoLog: presented=\(vc)")
            if vc.isKind(of: UIActivityViewController.self) || vc.isKind(of: NativePackageViewController.self) || vc.isKind(of: UINavigationController.self) {
                rootVC.dismiss(animated: true)
            }
        }
        
        DispatchQueue.global(qos: .default).async {
            PackageListManager.shared.initWait()
            DispatchQueue.main.async {
                if url.scheme == "file" {
                    if url.pathExtension == "deb" {
                        // The file is a deb. Open the package view controller to that file.
                        
                        let tmpdir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID.init().uuidString)
                        let newurl = tmpdir.appendingPathComponent(self.aptEncoded(string: url.lastPathComponent))
                        try! FileManager.default.createDirectory(at: tmpdir, withIntermediateDirectories: false)
                        try! FileManager.default.copyItem(at: url, to: newurl)
                        NSLog("SileoLog: newurl=\(newurl)")
                        
                        if options[UIApplication.OpenURLOptionsKey.openInPlace] as! Bool == false {
                            try! FileManager.default.removeItem(at: url)
                        }
                        
                        guard let package = PackageListManager.shared.package(url: newurl) else {
                            let alert = UIAlertController(title: "Bad Deb", message: "The provided deb file could not be read", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Ok", style: .cancel))
                            self.window?.rootViewController?.present(alert, animated: true, completion: nil)
                            return
                        }
                        let view = NativePackageViewController.viewController(for: package) as! PackageViewController
                        view.isPresentedModally = true
                        SileoAppDelegate.presentController(UINavigationController(rootViewController: view))
                    } else {
                        guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                              let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
                              let sourcesNavNV = sourcesSVC.viewControllers[0] as? SileoNavigationController,
                              let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController,
                              url.startAccessingSecurityScopedResource() else {
                                  return
                              }
                        sourcesVC.importRepos(fromURL: url)
                        url.stopAccessingSecurityScopedResource()
                    }
                } else {
                    // presentModally ignored; we always present modally for an external URL open.
                    var presentModally = false
                    if let viewController = URLManager.viewController(url: url, isExternalOpen: true, presentModally: &presentModally) {
                        SileoAppDelegate.presentController(viewController)
                    }
                }
            }
        }
        
        if url.host == "source" && url.scheme == "sileo" {
            guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
                let sourcesNavNV = sourcesSVC.viewControllers[0] as? SileoNavigationController,
                let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController else {
                return false
            }
            let newURL = url.absoluteURL
            tabBarController.selectedViewController = sourcesSVC
            sourcesVC.presentAddSourceEntryField(url: newURL)
        }
        return true
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .default).async { DispatchQueue.main.async {
            if self.window?.rootViewController?.presentedViewController != nil {
                return
            }
            self.application_(application, performActionFor: shortcutItem, completionHandler: completionHandler)
        }}
    }
    
    func application_(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let tabBarController = TabBarController.singleton,
              let controllers = tabBarController.viewControllers,
              let sourcesSVC = controllers[2] as? SourcesSplitViewController,
              let sourcesNVC = sourcesSVC.viewControllers[0] as? SileoNavigationController,
              let sourcesVC = sourcesNVC.viewControllers[0] as? SourcesViewController,
              let packageListNVC = controllers[3] as? SileoNavigationController,
              let packageListVC = packageListNVC.viewControllers[0] as? PackageListViewController
        else {
            return
        }
        
        if shortcutItem.type.hasSuffix(".UpgradeAll") {
            if DownloadManager.shared.queueRunning {
                tabBarController.presentPopupController()
                return
            }
            
            tabBarController.selectedViewController = packageListNVC
            
            let title = String(localizationKey: "Sileo")
            let msg = String(localizationKey: "Upgrade_All_Shortcut_Processing_Message")
            let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
            SileoAppDelegate.presentController(alert)
            
            sourcesVC.refreshSources(forceUpdate: false, forceReload: true, isBackground: false, useRefreshControl: true, useErrorScreen: true, completion: { _, _ in
                PackageListManager.shared.upgradeAll(completion: {
                    if UserDefaults.standard.bool(forKey: "AutoConfirmUpgradeAllShortcut", fallback: false) {
                        let downloadMan = DownloadManager.shared
// already reloadData(recheckPackages: true) in PackageListManager.shared.upgradeAll
//                        downloadMan.reloadData(recheckPackages: false)
                        downloadMan.viewController.confirmQueued(self)
                    }
                    //ignore UpgradeAllAutoQueue, always Show Queue on Upgrade All Shortcut
                    tabBarController.presentPopupController()
                    alert.dismiss(animated: true, completion: nil)
                })
            })
        } else if shortcutItem.type.hasSuffix(".Refresh") {
            tabBarController.selectedViewController = sourcesSVC
            sourcesVC.refreshSources(forceUpdate: false, forceReload: true, isBackground: false, useRefreshControl: true, useErrorScreen: true, completion: nil)
        } else if shortcutItem.type.hasSuffix(".AddSource") {
            tabBarController.selectedViewController = sourcesSVC
            sourcesVC.addSource(nil)
        } else if shortcutItem.type.hasSuffix(".Packages") {
            tabBarController.selectedViewController = packageListNVC
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        UIColor.isTransitionLockedForiOS13Bug = true
        
        if #available(iOS 13.0, *) {
            scheduleTasks()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        NSLog("SileoLog: applicationWillEnterForeground")
        UIColor.isTransitionLockedForiOS13Bug = false
    }
    
    @available(iOS 13.0, *)
    private func handleRefreshTask(_ task: BGTask) {
        func _return() {
            task.setTaskCompleted(success: true)
            scheduleRefreshTask()
        }
        backgroundRepoRefreshTask {
            return _return()
        }
    }
    
    @available(iOS 13.0, *)
    private func scheduleRefreshTask() {
        NSLog("SileoLog: scheduleRefreshTask")
        let fetchTask = BGAppRefreshTaskRequest(identifier: "sileo.backgroundrefresh")
        fetchTask.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(fetchTask)
        } catch {
            NSLog("SileoLog: Unable to submit task: \(error.localizedDescription)")
        }
    }
    
    @available(iOS 13.0, *)
    private func scheduleTasks() {
        scheduleRefreshTask()
    }
}

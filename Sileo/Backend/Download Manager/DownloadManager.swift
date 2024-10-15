//
//  DownloadManager.swift
//  Sileo
//
//  Created by CoolStar on 8/2/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

public enum DownloadManagerQueue: Int {
    case upgrades
    case installations
    case uninstallations
    case installdeps
    case uninstalldeps
    case none
}

final class DownloadManager {
    public static let lockStateChangeNotification = Notification.Name("SileoDownloadManagerLockStateChanged")
    
    private static let aptQueueContext = 50
    private static let aptQueueKey = DispatchSpecificKey<Int>()
    public static let aptQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Sileo.AptQueue", qos: .userInitiated)
        queue.setSpecific(key: aptQueueKey, value: aptQueueContext)
        return queue
    }()
    
    enum Error: LocalizedError {
        case hashMismatch(packageHash: String, refHash: String)
        case untrustedPackage(packageID: String)
        case debugNotAllowed
        
        public var errorDescription: String? {
            switch self {
            case let .hashMismatch(packageHash, refHash):
                return String(format: String(localizationKey: "Download_Hash_Mismatch", type: .error), packageHash, refHash)
            case let .untrustedPackage(packageID):
                return String(format: String(localizationKey: "Untrusted_Package", type: .error), packageID)
            case .debugNotAllowed:
                return "Packages cannot be added to the queue during install"
            }
        }
    }
    
    enum PackageHashType: String, CaseIterable {
        case sha256
        case sha512
        
        var hashType: HashType {
            switch self {
            case .sha256: return .sha256
            case .sha512: return .sha512
            }
        }
    }
    
    public static let shared = DownloadManager()
    
    public var lockedForInstallation = false {
        didSet {
            NSLog("SileoLog: lockedForInstallation: \(oldValue) -> \(lockedForInstallation)")
            // NotificationCenter.default.post(name: DownloadManager.lockStateChangeNotification, object: nil)
        }
    }
    
    public var queueStarted = false
    public var totalProgress = CGFloat(0)
    
//    private static let dataQueueContext = 50
//    private static let dataQueueKey = DispatchSpecificKey<Int>()
//    private static let dataQueue: DispatchQueue = {
//        let queue = DispatchQueue(label: "Sileo.dataQueue", qos: .userInitiated)
//        queue.setSpecific(key: dataQueueKey, value: dataQueueContext)
//        return queue
//    }()
        private static let dataQueueContext = aptQueueContext
        private static let dataQueueKey = aptQueueKey
        private static let dataQueue = aptQueue
    
    struct TSyncVars {
        public var upgrades = SafeSet<DownloadPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var installations = SafeSet<DownloadPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var uninstallations = SafeSet<DownloadPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var installdeps = SafeSet<DownloadPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var uninstalldeps = SafeSet<DownloadPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var errors = SafeSet<APTBrokenPackage>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        
        public var queuedDownloads = SafeDictionary<String,Download>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        public var cachedDownloadFiles = SafeArray<URL>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
        
        public var repoDownloadOverrideProviders = SafeDictionary<String, Set<AnyHashable>>(queue: dataQueue, key: dataQueueKey, context: dataQueueContext)
    }
    
    public var vars = TSyncVars()
    
    public var viewController: DownloadsTableViewController
    
    public var currentDownloads = 0
    public var maxParallelDownloads = 5
    public var currentDownloadSession:UInt32 = 0
    
    init() {
        viewController = DownloadsTableViewController(nibName: "DownloadsTableViewController", bundle: nil)
    }
    
    public func installingPackages() -> Int {
        self.vars.upgrades.count + self.vars.installations.count + self.vars.installdeps.count
    }
    
    public func uninstallingPackages() -> Int {
        self.vars.uninstallations.count + self.vars.uninstalldeps.count
    }
    
    public func operationCount() -> Int {
        self.vars.upgrades.count + self.vars.installations.count + self.vars.uninstallations.count + self.vars.installdeps.count + self.vars.uninstalldeps.count
    }
        
    public func downloadingPackages() -> Int {
        var downloadsCount = 0
        for keyValue in self.vars.queuedDownloads.raw where keyValue.value.progress < 1 {
            downloadsCount += 1
        }
        return downloadsCount
    }
    
    public func readyPackages() -> Int {
        var readyCount = 0
        for keyValue in self.vars.queuedDownloads.raw {
            let download = keyValue.value
            if download.progress == 1 && download.success == true {
                readyCount += 1
            }
        }
        return readyCount
    }
    
    public func verifyComplete() -> Bool {
        let allRawDownloads = self.vars.upgrades.raw.union(self.vars.installations.raw).union(self.vars.installdeps.raw)
        for dlPackage in allRawDownloads {
            guard let download = self.vars.queuedDownloads[dlPackage.package.package],
                  download.success else { return false }
        }
        return true
    }
    
    private func startPackageDownload(download: Download) {
        NSLog("SileoLog: startPackageDownload \(download.package.package)")
        
        guard download.session == self.currentDownloadSession else {
            return
        }
        
        let package = download.package
        var filename = package.filename ?? ""
        
        var packageRepo: Repo?
        for repo in RepoManager.shared.repoList where repo.rawEntry == package.sourceFile {
            packageRepo = repo
        }
        
        if let local_deb = package.local_deb {
            filename = URL(fileURLWithPath: local_deb).absoluteString
        } else if !filename.hasPrefix("https://") && !filename.hasPrefix("http://") {
            filename = URL(string: packageRepo?.rawURL ?? "")?.appendingPathComponent(filename).absoluteString ?? ""
        }
        
        // If it's a local file we can verify it immediately
        if self.verify(download: download) {
            download.progress = 1
            download.success = true
            download.completed = true
            Self.aptQueue.async { [self] in
                if self.verifyComplete() {
                    self.viewController.reloadControlsOnly()
                } else {
                    NSLog("SileoLog: startMoreDownloads (startPackageDownload) 1")
                    startMoreDownloads()
                }
            }
            return
        }
        
        download.backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            download.task?.cancel()
            if let backgroundTaskIdentifier = download.backgroundTask {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
            download.backgroundTask = nil
        })
        
        // See if theres an overriding web URL for downloading the package from
        currentDownloads += 1
        self.overrideDownloadURL(package: package, repo: packageRepo) { errorMessage, url in
            if url == nil && errorMessage != nil {
                self.currentDownloads -= 1
                download.failureReason = errorMessage
                DispatchQueue.main.async {
                    self.viewController.reloadDownload(package: download.package)
                    TabBarController.singleton?.updatePopup()
                }
                return
            }
            let downloadURL = url ?? URL(string: filename)
            download.started = true
            download.failureReason = nil
            download.task = RepoManager.shared.queue(from: downloadURL, progress: { task, progress in DispatchQueue.main.async {
                //now in main queue
                NSLog("SileoLog: download progress \(task.task)")
                //in main queue (sync with UI), check task cancelled
                guard task.task != nil else {
                    return
                }
                guard download.session == self.currentDownloadSession else {
                    return
                }
                
                download.message = nil
                download.progress = CGFloat(progress.fractionCompleted)
                download.totalBytesWritten = progress.total
                download.totalBytesExpectedToWrite = progress.expected
                
                self.viewController.reloadDownload(package: package)
                
            }}, success: { task, status, fileURL in DispatchQueue.main.async {
                //now in main queue
                NSLog("SileoLog: download success \(task.task)")

                //in main queue (sync with UI), check task cancelled
                guard task.task != nil else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                guard download.session == self.currentDownloadSession else {
                    return
                }
                
                self.currentDownloads -= 1
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes?[FileAttributeKey.size] as? Int
                let fileSizeStr = String(format: "%ld", fileSize ?? 0)
                
                download.message = nil
                
                if let backgroundTaskIdentifier = download.backgroundTask {
                    download.backgroundTask = nil
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
                
                if package.local_deb==nil && (fileSizeStr != package.size) {
                    download.failureReason = String(format: String(localizationKey: "Download_Size_Mismatch", type: .error),
                                                    package.size ?? "nil", fileSizeStr)
                    download.success = false
                    download.progress = 0
                    
                    NSLog("SileoLog: startMoreDownloads (startPackageDownload) 3")
                    self.startMoreDownloads()
                    
                } else {
                    
                    do {
                        download.success = try self.verify(download: download, fileURL: fileURL)
                    } catch let error {
                        download.success = false
                        download.failureReason = error.localizedDescription
                    }
                    if download.success {
                        download.progress = 1
                    } else {
                        download.progress = 0
                    }
                    
#if TARGET_SANDBOX || targetEnvironment(simulator)
                    try? FileManager.default.removeItem(at: fileURL)
#endif
                    
                    var completed = false
                    
                    //sync not async (is this "aptQueue" necessary?)
                    Self.aptQueue.sync {
                        completed = self.verifyComplete()
                    }
                    
                    if completed {
                        self.viewController.reloadDownload(package: download.package)
                        TabBarController.singleton?.updatePopup()
                        self.viewController.reloadControlsOnly()
                    } else {
                        NSLog("SileoLog: startMoreDownloads (startPackageDownload) 2")
                        self.startMoreDownloads()
                    }
                    
                    return
                }
                
            }}, failure: { task, statusCode, error in DispatchQueue.main.async {
                //now in main queue
                NSLog("SileoLog: download failure \(task?.task)")

                //in main queue (sync with UI), check task cancelled
                guard task?.task != nil else {
                    return
                }
                guard download.session == self.currentDownloadSession else {
                    return
                }
                
                self.currentDownloads -= 1
                download.failureReason = error?.localizedDescription ?? String(format: String(localizationKey: "Download_Failing_Status_Code", type: .error), statusCode)
                download.message = nil
                
                if let backgroundTaskIdentifier = download.backgroundTask {
                    download.backgroundTask = nil
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
                
                self.viewController.reloadDownload(package: download.package)
                self.viewController.reloadControlsOnly()
                TabBarController.singleton?.updatePopup()
                    
                NSLog("SileoLog: startMoreDownloads (startPackageDownload) 4")
                self.startMoreDownloads()
            }}, waiting: { task, message in DispatchQueue.main.async {
                //now in main queue
                NSLog("SileoLog: download waiting \(task.task)")

                //in main queue (sync with UI), check task cancelled
                guard task.task != nil else {
                    return
                }
                guard download.session == self.currentDownloadSession else {
                    return
                }
                
                download.message = message
                self.viewController.reloadDownload(package: package)
            }})
            download.task?.resume()
            
            self.viewController.reloadDownload(package: package)
        }
    }
    
    func startMoreDownloads() {
        NSLog("SileoLog: startMoreDownloads")
//        Thread.callStackSymbols.forEach{NSLog("SileoLog: callstack=\($0)")}
        DownloadManager.aptQueue.async { [self] in
            // We don't want more than one download at a time
            guard currentDownloads <= maxParallelDownloads else { return }
            // Get a list of downloads that need to take place
            let allRawDownloads = self.vars.upgrades.raw.union(self.vars.installations.raw).union(self.vars.installdeps.raw)
            for dlPackage in allRawDownloads {
                // Get the download object, we don't want to create multiple
                let download: Download
                let package = dlPackage.package
                if let tmp = self.vars.queuedDownloads[package.package] {
                    download = tmp
                } else {
                    download = Download(package: package, session: self.currentDownloadSession)
                    self.vars.queuedDownloads[package.package] = download
                }
                
                // Means download has already started / completed
                if download.queued { continue }
                download.queued = true
                startPackageDownload(download: download)
                
                guard currentDownloads <= maxParallelDownloads else { break }
            }
        }
    }
 
    public func queuedDownload(package: String) -> Download? {
        self.vars.queuedDownloads[package]
    }
    
    private func aptEncoded(string: String, isArch: Bool) -> String {
        var encodedString = string.replacingOccurrences(of: "_", with: "%5f")
        encodedString = encodedString.replacingOccurrences(of: ":", with: "%3a")
        if isArch {
            encodedString = encodedString.replacingOccurrences(of: ".", with: "%2e")
        }
        return encodedString
    }
    
    private func verify(download: Download) -> Bool {
        let package = download.package
        
        let packageID = aptEncoded(string: package.package, isArch: false)
        let version = aptEncoded(string: package.version, isArch: false)
        let architecture = aptEncoded(string: package.architecture ?? "", isArch: true)
        
        let destFileName = "\(CommandPath.prefix)/var/cache/apt/archives/\(packageID)_\(version)_\(architecture).deb"
        let destURL = URL(fileURLWithPath: destFileName)
        
        if let local_deb = package.local_deb {
            moveFileAsRoot(from: URL(fileURLWithPath: local_deb), to: URL(fileURLWithPath: destFileName))
            self.vars.cachedDownloadFiles.append(URL(fileURLWithPath: local_deb))
            package.local_deb = destFileName
            return FileManager.default.fileExists(atPath: destFileName)
        }
        
        let packageControl = package.rawControl
        let supportedHashTypes = PackageHashType.allCases.compactMap { type in packageControl[type.rawValue].map { (type, $0) } }
        let packageContainsHashes = !supportedHashTypes.isEmpty
        
        guard packageContainsHashes else { return false }
        
        let packageIsValid = supportedHashTypes.allSatisfy {
            let hash = packageControl[$1]
            guard let refHash = destURL.hash(ofType: $0.hashType),
                  refHash == hash else { return false }
            return true
        }
        guard packageIsValid else {
            return false
        }
        
        return true
    }
    
    private func verify(download: Download, fileURL: URL) throws -> Bool {
        let package = download.package
        let packageControl = package.rawControl
        
        if package.local_deb==nil {
            let supportedHashTypes = PackageHashType.allCases.compactMap { type in packageControl[type.rawValue].map { (type, $0) } }
            let packageContainsHashes = !supportedHashTypes.isEmpty
            
            guard packageContainsHashes else {
                throw Error.untrustedPackage(packageID: package.package)
            }
            
            var badHash = ""
            var badRefHash = ""
            
            let packageIsValid = supportedHashTypes.allSatisfy {
                let hash = $1
                guard let refHash = fileURL.hash(ofType: $0.hashType) else { return false }
              
                if hash != refHash {
                    badHash = hash
                    badRefHash = refHash
                    return false
                } else {
                    return true
                }
            }
            guard packageIsValid else {
                throw Error.hashMismatch(packageHash: badHash, refHash: badRefHash)
            }
        }
        
        #if !TARGET_SANDBOX && !targetEnvironment(simulator)
        let packageID = aptEncoded(string: package.package, isArch: false)
        let version = aptEncoded(string: package.version, isArch: false)
        let architecture = aptEncoded(string: package.architecture ?? "", isArch: true)
        
        let destFileName = "\(CommandPath.prefix)/var/cache/apt/archives/\(packageID)_\(version)_\(architecture).deb"
        let destURL = URL(fileURLWithPath: destFileName)

        moveFileAsRoot(from: fileURL, to: destURL)
        #endif
        self.vars.cachedDownloadFiles.append(fileURL)
        return true
    }
    
    //running in aptQueue
    private func recheckTotalOps() throws {
        NSLog("SileoLog: recheckTotalOps")
        if Thread.isMainThread {
            fatalError("This cannot be called from the main thread!")
        }
        
        // Clear any current depends
        self.vars.installdeps.removeAll()
        self.vars.uninstalldeps.removeAll()
        self.vars.errors.removeAll()
        
        // Get a total of depends to be installed and break if empty
        let installationsAndUpgrades = self.vars.installations.raw.union(self.vars.upgrades.raw)
        guard !(installationsAndUpgrades.isEmpty && self.vars.uninstallations.isEmpty) else {
            return
        }
        let all = (installationsAndUpgrades.union(self.vars.uninstallations.raw)).map { $0.package }
        do {
            // Run the dep accelerator for any packages that have not already been cared about
            try DependencyResolverAccelerator.shared.getDependencies(packages: all)
        } catch {
            throw error
        }
        #if TARGET_SANDBOX || targetEnvironment(simulator)
        return
        #endif
        var aptOutput: APTOutput
        do {
            // Get the full list of packages to be installed and removed from apt
            aptOutput = try APTWrapper.operationList(installList: installationsAndUpgrades, removeList: self.vars.uninstallations.raw)
            NSLog("SileoLog: aptOutput=\(aptOutput.operations), \(aptOutput.conflicts)")
        } catch {
            throw error
        }
        
        // Get every package to be uninstalled
        var uninstallIdentifiers = [String]()
        for operation in aptOutput.operations where operation.type == .remove {
            uninstallIdentifiers.append(operation.packageID)
        }
        
        var uninstallations = self.vars.uninstallations.raw
        let rawUninstalls = PackageListManager.shared.packages(identifiers: uninstallIdentifiers, sorted: false, packages: Array(PackageListManager.shared.installedPackages.values))
        guard rawUninstalls.count == uninstallIdentifiers.count else {
            rawUninstalls.map({NSLog("SileoLog: rawUninstalls=\($0.package) \($0.package)")})
            uninstallIdentifiers.map({NSLog("SileoLog: uninstallIdentifiers=\($0)")})
            throw APTParserErrors.blankJsonOutput(error: "Uninstall Identifiers Mismatch")
        }
        var uninstallDeps = Set<DownloadPackage>(rawUninstalls.compactMap { DownloadPackage(package: $0) })
        
        // Get the list of packages to be installed, including depends
        var installDepOperation = [String: (String, [String])]()
        for operation in aptOutput.operations where operation.type == .install {

            //there may be multiple repos in the release: \
            //{"Version":"2021.07.18","Package":"chariz-keyring","Release":"192.168.2.171, local-deb [all]","Type":"Inst"}
            //{"Version":"62","Package":"lsof","Release":"roothide.github.io, iosjb.top [iphoneos-arm64e]","Type":"Inst"}
            //{"Version":"0.3.8","Package":"com.nan.dpkg-fill","Release":"invalidunit.github.io [iphoneos-arm64e]","Type":"Inst"}
            
            var hosts = [String]()
            if let releases = operation.release?.split(separator: ",") {
                for release in releases {
                    guard let host = release.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { continue }
                    hosts.append(String(host))
                }
            }

            installDepOperation[operation.packageID] = (operation.version, hosts)
        }
        NSLog("SileoLog: installDepOperation=\(installDepOperation)")
        var rawInstalls = ContiguousArray<Package>()
        for (packageID, (packageVersion,hosts)) in installDepOperation {
                
            if hosts.contains("local-deb") { //preferred local package
                if let localPackage = PackageListManager.shared.localPackages[packageID] {
                    if checkRootHide(localPackage) {
                        if localPackage.version == packageVersion {
                            NSLog("SileoLog: using local package=\(localPackage.package),\(localPackage.version),\(localPackage.local_deb)")
                            rawInstalls.append(localPackage)
                        }
                    }
                }
            } else {
                //hosts may be empty?
                hostLoop: for host in hosts {
                    // there may be multiple repos with the same host
                    for repo in RepoManager.shared.repoList where repo.url?.host == host {
                        if let repoPackage = PackageListManager.shared.package(identifier: packageID, version: packageVersion, packages: repo.packageArray)
                        {
                            NSLog("SileoLog: using repoPackage=\(repoPackage.package),\(repoPackage.version),\(repoPackage.sourceRepo?.url)")
                            if checkRootHide(repoPackage) {
                                rawInstalls.append(repoPackage)
                                break hostLoop
                            }
                        }
                    }
                }
            }
        }
        
        rawInstalls.map({NSLog("SileoLog: rawInstalls: \($0.package)=\($0.version) \($0.local_deb ?? $0.sourceRepo?.url)")})

        guard rawInstalls.count == installDepOperation.count else {
            throw APTParserErrors.blankJsonOutput(error: "Install Identifier Mismatch for Identifiers")
        }
        var installDeps = Set<DownloadPackage>(rawInstalls.compactMap { DownloadPackage(package: $0) })
        var installations = self.vars.installations.raw
        var upgrades = self.vars.upgrades.raw

        //Remove the package resolved by apt from the user-specified installation packages
        if aptOutput.conflicts.isEmpty {
            installations.removeAll { uninstallDeps.contains($0) }
            uninstallations.removeAll { installDeps.contains($0) }
            
            installations.removeAll { !installDeps.contains($0) }
            upgrades.removeAll { !installDeps.contains($0) }
            uninstallations.removeAll { !uninstallDeps.contains($0) }
            uninstallDeps.removeAll { uninstallations.contains($0) }
            installDeps.removeAll { installations.contains($0) }
            installDeps.removeAll { upgrades.contains($0) }
        }
  
        self.vars.upgrades.setTo(upgrades)
        self.vars.installations.setTo(installations)
        self.vars.installdeps.setTo(installDeps)
        self.vars.uninstallations.setTo(uninstallations)
        self.vars.uninstalldeps.setTo(uninstallDeps)
        self.vars.errors.setTo(Set<APTBrokenPackage>(aptOutput.conflicts))
        
        NSLog("SileoLog: upgrades=\(self.vars.upgrades.count), installations=\(self.vars.installations.count), installdeps=\(self.vars.installdeps.count) uninstallations=\(self.vars.uninstallations.count) uninstalldeps=\(self.vars.uninstalldeps.count) errors=\(self.vars.errors.count)")
        for p in self.vars.upgrades.raw { NSLog("SileoLog: self.upgrades: \(p.package.package)=\(p.package.version), \(p.package.local_deb ?? p.package.sourceRepo?.url)") }
        for p in self.vars.installations.raw { NSLog("SileoLog: self.installations: \(p.package.package)=\(p.package.version), \(p.package.local_deb ?? p.package.sourceRepo?.url)") }
        for p in self.vars.installdeps.raw { NSLog("SileoLog: self.installdeps: \(p.package.package)=\(p.package.version), \(p.package.local_deb ?? p.package.sourceRepo?.url)") }
        for p in self.vars.uninstallations.raw { NSLog("SileoLog: self.uninstallations: \(p.package.package)=\(p.package.version), \(p.package.local_deb ?? p.package.sourceRepo?.url)") }
        for p in self.vars.uninstalldeps.raw { NSLog("SileoLog: self.uninstalldeps: \(p.package.package)=\(p.package.version), \(p.package.local_deb ?? p.package.sourceRepo?.url)") }
    }
    
    private func checkInstalled() {
        let installedPackages = PackageListManager.shared.installedPackages.values
        for package in installedPackages {
            if package.eFlag == .reinstreq {
                guard let newestPackage = PackageListManager.shared.newestPackage(identifier: package.package, repoContext: nil) else {
                    continue
                }
                
                if !checkRootHide(newestPackage) {
                    continue
                }

                let downloadPackage = DownloadPackage(package: newestPackage)
                
                if !self.vars.installations.contains(downloadPackage) && !self.vars.uninstallations.contains(downloadPackage) {
                    NSLog("SileoLog: reinstreq \(downloadPackage.package)")
                    self.vars.installations.insert(downloadPackage)
                    //manually resolve package here so that apt can be able to reinstall it
                    DownloadManager.aptQueue.async {
                        try? DependencyResolverAccelerator.shared.getDependencies(packages: [downloadPackage.package])
                    }
                }
            } else if package.eFlag == .ok {
                let downloadPackage = DownloadPackage(package: package)
                if package.wantInfo == .deinstall || package.wantInfo == .purge || package.status == .halfconfigured {
                    if !self.vars.installations.contains(downloadPackage) && !self.vars.uninstallations.contains(downloadPackage) {
                        NSLog("SileoLog: wantInfo \(downloadPackage.package.package) = \(downloadPackage.package.wantInfo.rawValue)")
                        self.vars.uninstallations.insert(downloadPackage)
                    }
                }
            }
        }
    }
    
    public func cancelDownloads() {
        for download in self.vars.queuedDownloads.raw.values {
            download.task?.cancel()
            if let backgroundTaskIdentifier = download.backgroundTask {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
        }
        //how about cachedDownloadFiles?
        self.vars.queuedDownloads.removeAll()
        currentDownloads = 0
    }
    
    public func removeAllItems() {
        self.vars.upgrades.removeAll()
        self.vars.installdeps.removeAll()
        self.vars.installations.removeAll()
        self.vars.uninstalldeps.removeAll()
        self.vars.uninstallations.removeAll()
        self.vars.errors.removeAll()
        for download in self.vars.queuedDownloads.raw.values {
            download.task?.cancel()
            if let backgroundTaskIdentifier = download.backgroundTask {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
        }
        self.vars.queuedDownloads.removeAll()
        currentDownloads = 0
        self.checkInstalled()
    }
    
    public func reloadData(recheckPackages: Bool) {
        reloadData(recheckPackages: recheckPackages, completion: nil)
    }
    
    public func reloadData(recheckPackages: Bool, completion: (() -> Void)?) {
        NSLog("SileoLog: DownloadManager.reloadData \(recheckPackages) \(completion)")
        DownloadManager.aptQueue.async { [self] in
            if recheckPackages {
                do {
                    try self.recheckTotalOps()
                } catch {
                    removeAllItems()
                    viewController.cancelDownload(nil)
                    TabBarController.singleton?.displayError(error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                self.viewController.reloadData()
                TabBarController.singleton?.updatePopup(completion: completion)
                NotificationCenter.default.post(name: PackageListManager.stateChange, object: nil)
            }
        }
    }
    
    public func find(package: Package) -> DownloadManagerQueue {
        let downloadPackage = DownloadPackage(package: package)
        if self.vars.installations.contains(downloadPackage) {
            return .installations
        } else if self.vars.uninstallations.contains(downloadPackage) {
            return .uninstallations
        } else if self.vars.upgrades.contains(downloadPackage) {
            return .upgrades
        } else if self.vars.installdeps.contains(downloadPackage) {
            return .installdeps
        } else if self.vars.uninstalldeps.contains(downloadPackage) {
            return .uninstalldeps
        }
        return .none
    }
    
    public func find(package: String) -> DownloadManagerQueue {
        if self.vars.installations.contains(where: { $0.package.package == package }) {
            return .installations
        } else if self.vars.uninstallations.contains(where: { $0.package.package == package }) {
            return .uninstallations
        } else if self.vars.upgrades.contains(where: { $0.package.package == package }) {
            return .upgrades
        } else if self.vars.installdeps.contains(where: { $0.package.package == package }) {
            return .installdeps
        } else if self.vars.uninstalldeps.contains(where: { $0.package.package == package }) {
            return .uninstalldeps
        }
        return .none
    }
    
    public func remove(package: String) {
        self.vars.installations.remove { $0.package.package == package }
        self.vars.upgrades.remove { $0.package.package == package }
        self.vars.installdeps.remove { $0.package.package == package }
        self.vars.uninstallations.remove { $0.package.package == package }
        self.vars.uninstalldeps.remove { $0.package.package == package }
    }
    
    
    private func checkRootlessV2(package: Package, fileURL: URL) {
        NSLog("SileoLog: checkRootlessV2 \(package.package) \(fileURL)")
        
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false, attributes: nil)
        
        var (status, output, errorOutput) = spawn(command: CommandPath.dpkgdeb, args: ["dpkg-deb", "-R", rootfs(fileURL.path), rootfs(temp.path)], root: true)
        guard status==0 else {return}
        
        let controlFilePath = temp.path.appending("/DEBIAN/control")
        
        spawn(command: CommandPath.chmod, args: ["chmod", "0666", rootfs(controlFilePath)], root: true)
        spawn(command: CommandPath.chmod, args: ["chmod", "0777", rootfs(temp.path.appending("/DEBIAN"))], root: true)
        
        guard var controlFileData = try? String(contentsOfFile: controlFilePath, encoding: .utf8) else {
            NSLog("SileoLog: read err \(controlFilePath)")
            return
        }
        
        let pattern = "^Architecture:\\s*(.+)\\s*$"
        let regexp = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        let range = NSRange(location: 0, length: controlFileData.count)
        let archNSRange = regexp.rangeOfFirstMatch(in: controlFileData, range: range)
        guard let archRange = Range(archNSRange, in: controlFileData) else { return }
        let archString = String(controlFileData[archRange])
        let archStringRange = NSRange(location: 0, length: archString.count)
        let origArch = regexp.stringByReplacingMatches(in: archString, range: archStringRange, withTemplate: "$1")
        
        controlFileData = regexp.stringByReplacingMatches(in: controlFileData, range: range, withTemplate: "Architecture: all")
        NSLog("SileoLog: origArch=\(origArch) controlFileData=\(controlFileData)")

        do {
            try controlFileData.write(toFile: controlFilePath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("SileoLog: write err \(error)")
            return
        }
        
        spawn(command: CommandPath.chmod, args: ["chmod", "0644", rootfs(controlFilePath)], root: true)
        spawn(command: CommandPath.chmod, args: ["chmod", "0755", rootfs(temp.path.appending("/DEBIAN"))], root: true)
        
        var newPkgPath = temp.path
        if FileManager.default.fileExists(atPath: temp.path.appending("/var/jb")) {
            newPkgPath = temp.path.appending("/var/jb")
            spawn(command: CommandPath.mv, args: ["mv", "-f", rootfs(temp.path.appending("/DEBIAN")), rootfs(newPkgPath)], root: true)
        }
        
        let outPath = temp.path.appending(".deb")
        
        (status, output, errorOutput) = spawn(command: CommandPath.dpkgdeb, args: ["dpkg-deb", "-b", rootfs(newPkgPath), rootfs(outPath)], root: true)
        guard status==0 else {return}

        guard let newPackage = PackageListManager.shared.package(url: URL(fileURLWithPath: outPath)) else {
            return
        }
        
        if checkRootHide(newPackage) {
            newPackage.origArchitecture = origArch
            self.add(package: newPackage, queue: .installations)
            self.reloadData(recheckPackages: true)
        }
    }
    
    private func patchPackage(package: Package, fileURL: URL) {
            let packageID = self.aptEncoded(string: package.package, isArch: false)
            let version = self.aptEncoded(string: package.version, isArch: false)
            let architecture = self.aptEncoded(string: package.architecture ?? "", isArch: true)
            
            let extractionPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try! FileManager.default.createDirectory(at: extractionPath, withIntermediateDirectories: false, attributes: nil)
            
            let destFileName = "/\(extractionPath.path)/\(packageID)_\(version)_\(architecture).deb"
            let destURL = URL(fileURLWithPath: destFileName)
            NSLog("SileoLog: destURL=\(destURL.path)")
            try! FileManager.default.moveItem(at: fileURL, to: destURL)
        
            if IsAppAvailable("com.roothide.patcher") {
                if ShareFileToApp("com.roothide.patcher", destFileName) {
                    return
                }
            }
    
            let activity = UIActivityViewController(activityItems: [destURL], applicationActivities: nil)
            
            //for ipad, don't touch
            let sv = TabBarController.singleton!.view!
            activity.popoverPresentationController?.sourceView = sv
            activity.popoverPresentationController?.sourceRect = CGRect(x: sv.bounds.midX, y: sv.bounds.height, width: 0, height: 0)
            activity.popoverPresentationController?.permittedArrowDirections = UIPopoverArrowDirection.down
            
            
            var controller:UIViewController = TabBarController.singleton!
            while controller.presentedViewController != nil && controller.presentedViewController?.isBeingDismissed==false {
                controller = controller.presentedViewController!
            }
            controller.present(activity, animated: true)
    }
    
    // call in main queue
    private func downloadDeb(package: Package, msg: String, handler: @escaping ((Package,URL) -> Void)) {
        var task:EvanderDownloader?
        
        let alert = UIAlertController(title: msg, message: msg, preferredStyle: .alert)
        
        let cancel = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel) { _ in
            alert.dismiss(animated: true, completion: nil)
            task?.cancel()
        }
        alert.addAction(cancel)
        
        var controller:UIViewController = TabBarController.singleton!
        while controller.presentedViewController != nil && controller.presentedViewController?.isBeingDismissed==false {
            controller = controller.presentedViewController!
        }
        
        controller.present(alert, animated: true)
        
        func updateMsg(msg: String) {
            NSLog("SileoLog: updateMsg=\(msg)")
            DispatchQueue.main.async {
                alert.message = "\n \(msg) \n"
            }
        }
        
        func finishDownload(fileURL: URL) {
            NSLog("SileoLog: finishDownload=\(fileURL.path)")
            DispatchQueue.main.async {
                    alert.dismiss(animated: true, completion: {
                        handler(package,fileURL)
                })
            }
        }
        

        var filename = package.filename ?? ""
        
        var packageRepo: Repo?
        for repo in RepoManager.shared.repoList where repo.rawEntry == package.sourceFile {
            packageRepo = repo
        }
        
        if let local_deb = package.local_deb {
            finishDownload(fileURL: URL(fileURLWithPath: local_deb))
            return
        } else if !filename.hasPrefix("https://") && !filename.hasPrefix("http://") {
            filename = URL(string: packageRepo?.rawURL ?? "")?.appendingPathComponent(filename).absoluteString ?? ""
        }
        
        // See if theres an overriding web URL for downloading the package from
        self.overrideDownloadURL(package: package, repo: packageRepo) { errorMessage, url in
            if url == nil && errorMessage != nil {
                updateMsg(msg: "\(errorMessage)")
                return
            }
            let downloadURL = url ?? URL(string: filename)
            NSLog("SileoLog: downloadURL=\(downloadURL)")
            task = RepoManager.shared.queue(from: downloadURL, progress: { task, progress in
                var msg:String
                if progress.expected==NSURLSessionTransferSizeUnknown {
                    msg = "\(progress.total) bytes ..."
                } else {
                    msg = "\(Int(progress.fractionCompleted * 100))% ..."
                }
                updateMsg(msg: msg)
            }, success: { task, status, fileURL in
                
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes?[FileAttributeKey.size] as? Int
                let fileSizeStr = String(format: "%ld", fileSize ?? 0)
                
                if package.local_deb==nil && (fileSizeStr != package.size) {
                    let failureReason = String(format: String(localizationKey: "Download_Size_Mismatch", type: .error),
                                               package.size ?? "nil", fileSizeStr)
                    updateMsg(msg: "\(failureReason)")
                } else {
                    finishDownload(fileURL: fileURL)
                }
                
            }, failure: { task, statusCode, error in
                let failureReason = error?.localizedDescription ?? String(format: String(localizationKey: "Download_Failing_Status_Code", type: .error), statusCode)
                
                updateMsg(msg: "\(failureReason)")
                
            }, waiting: { task, message in
                updateMsg(msg: "\(message)")
            })
            task?.resume()
        }
    }
    
    private var patchAlert:UIAlertController?
    
    public func add(package: Package, queue: DownloadManagerQueue, approved: Bool = false) {
        NSLog("SileoLog: addPackage=\(package.name), queue=\(queue.rawValue), approved=\(approved) package=\(package.package), repo=\(package.sourceRepo?.url) depends=\(package.rawControl["depends"]) arch=\(package.architecture)")
//        Thread.callStackSymbols.forEach{NSLog("SileoLog: callstack=\($0)")}

        CanisterResolver.shared.ingest(packages: [package])
        
        if queue != .uninstallations && queue != .uninstalldeps {
            if !checkRootHide(package) {
                
                if package.tags.contains(.roothide) && FileManager.default.fileExists(atPath: jbroot("/usr/lib/libroot.dylib")) {
                    NSLog("SileoLog: roothide suppport: \(package.package)")
                    self.downloadDeb(package:package, msg: String(localizationKey: "Loading"), handler: self.checkRootlessV2)
                    return
                }
                
                func showPatchAlert() {
                    NSLog("SileoLog: not updated for roothide: \(package.package) \(package.architecture)")
                    
                    let title = String(localizationKey: "Not Updated")
                    
                    let msg = ["apt.procurs.us","ellekit.space"].contains(package.sourceRepo?.url?.host) ? String(localizationKey: "please contact @roothideDev to update it") : String(localizationKey: "\(package.package)\n\nYou can contact the developer of this package to update it for roothide, or you can try to convert it via roothide Patcher.")
                    
                    let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                    
                    let installedPatcher = PackageListManager.shared.installedPackage(identifier: "com.roothide.patcher") != nil
                    
                    let patchAction = UIAlertAction(title: String(localizationKey: installedPatcher ? "Convert" : "Get Patcher"), style: .destructive) { _ in
                        alert.dismiss(animated: true, completion: {
                            var presentModally = false
                            if installedPatcher {
                                self.downloadDeb(package:package, msg: String(localizationKey: "Downloading_Package_Status"), handler: self.patchPackage)
                            }
                            else if let packageview = URLManager.viewController(url: URL(string: "sileo://package/com.roothide.patcher"), isExternalOpen: true, presentModally: &presentModally) {
                                
                                var controller:UIViewController = TabBarController.singleton!
                                while controller.presentedViewController != nil && controller.presentedViewController?.isBeingDismissed==false {
                                    controller = controller.presentedViewController!
                                }
                                controller.present(packageview, animated: true)
                            }
                        })
                    }
                    
                    if ["apt.procurs.us","ellekit.space"].contains(package.sourceRepo?.url?.host)==false {
                        alert.addAction(patchAction)
                    }
                    
                    let okAction = UIAlertAction(title: (package.sourceRepo?.url?.host == "apt.procurs.us") ? String(localizationKey: "OK") : String(localizationKey: "Cancel"), style: .cancel) { _ in
                        alert.dismiss(animated: true, completion: nil)
                    }
                    alert.addAction(okAction)
                    
                    var controller:UIViewController = TabBarController.singleton!
                    while controller.presentedViewController != nil && controller.presentedViewController?.isBeingDismissed==false {
                        controller = controller.presentedViewController!
                    }
                    assert(self.patchAlert == nil)
                    controller.present(alert, animated: true)
                    self.patchAlert = alert
                }
                
                DispatchQueue.main.async {
                    if let patchAlert = self.patchAlert {
                        patchAlert.dismiss(animated: true, completion: {
                            self.patchAlert = nil
                            showPatchAlert()
                        })
                    } else {
                        showPatchAlert()
                    }
                }
                return
            }
        }
        

        let downloadPackage = DownloadPackage(package: package)
        let found = find(package: package.package)
        if found == queue { return }
        remove(downloadPackage: downloadPackage, queue: found)

        switch queue {
        case .none:
            return
        case .installations:
            self.vars.installations.insert(downloadPackage)
        case .uninstallations:
            if approved == false && isEssential(downloadPackage.package) {
                let message = String(format: String(localizationKey: "Essential_Warning"),
                                     "\n\(downloadPackage.package.name ?? downloadPackage.package.package)")
                let alert = UIAlertController(title: String(localizationKey: "Warning"),
                                              message: message,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .default, handler: { _ in
                    alert.dismiss(animated: true)
                }))
                alert.addAction(UIAlertAction(title: String(localizationKey: "Dangerous_Repo.Last_Chance.Continue"), style: .destructive, handler: { _ in
                    self.add(package: downloadPackage.package, queue: .uninstallations, approved: true)
                    self.reloadData(recheckPackages: true)
                }))
                TabBarController.singleton?.present(alert, animated: true)
                return
            }
            self.vars.uninstallations.insert(downloadPackage)
        case .upgrades:
            self.vars.upgrades.insert(downloadPackage)
        case .installdeps:
            self.vars.installdeps.insert(downloadPackage)
        case .uninstalldeps:
            self.vars.uninstalldeps.insert(downloadPackage)
        }
    }
    
    public func upgradeAll(packages: Set<Package>, _ completion: @escaping () -> ()) {
        Self.aptQueue.async { [self] in
            var packages = packages
            let mapped = self.vars.upgrades.map { $0.package.package }
            packages.removeAll { mapped.contains($0.package) }
            for package in packages {
                let downloadPackage = DownloadPackage(package: package)
                let found = find(package: package.package)
                if found == .upgrades { continue }
                remove(downloadPackage: downloadPackage, queue: found)
                self.vars.upgrades.insert(downloadPackage)
            }
            completion()
        }
    }
  
    public func remove(package: Package, queue: DownloadManagerQueue) {
        let downloadPackage = DownloadPackage(package: package)
        remove(downloadPackage: downloadPackage, queue: queue)
    }
    
    public func remove(downloadPackage: DownloadPackage, queue: DownloadManagerQueue) {
        switch queue {
        case .none:
            return
        case .installations:
            self.vars.installations.remove(downloadPackage)
        case .uninstallations:
            self.vars.uninstallations.remove(downloadPackage)
        case .upgrades:
            self.vars.upgrades.remove(downloadPackage)
        case .installdeps:
            self.vars.installdeps.remove(downloadPackage)
        case .uninstalldeps:
            self.vars.uninstalldeps.remove(downloadPackage)
        }
    }

    public func register(downloadOverrideProvider: DownloadOverrideProviding, repo: Repo) {
        if self.vars.repoDownloadOverrideProviders[repo.repoURL] == nil {
            self.vars.repoDownloadOverrideProviders[repo.repoURL] = Set()
        }
        self.vars.repoDownloadOverrideProviders[repo.repoURL]?.insert(downloadOverrideProvider.hashableObject)
    }
    
    public func deregister(downloadOverrideProvider: DownloadOverrideProviding, repo: Repo) {
        self.vars.repoDownloadOverrideProviders[repo.repoURL]?.remove(downloadOverrideProvider.hashableObject)
    }
    
    public func deregister(downloadOverrideProvider: DownloadOverrideProviding) {
        for keyVal in self.vars.repoDownloadOverrideProviders.raw {
            self.vars.repoDownloadOverrideProviders[keyVal.key]?.remove(downloadOverrideProvider.hashableObject)
        }
    }
    
    private func overrideDownloadURL(package: Package, repo: Repo?, completionHandler: @escaping (String?, URL?) -> Void) {
        guard let repo = repo,
              let providers = self.vars.repoDownloadOverrideProviders[repo.repoURL],
              !providers.isEmpty else {
            return completionHandler(nil, nil)
        }

        // The number of providers checked so far
        var checked = 0
        let total = providers.count
        for obj in providers {
            guard let downloadProvider = obj as? DownloadOverrideProviding else {
                continue
            }
            var willProvideURL = false
            willProvideURL = downloadProvider.downloadURL(for: package, from: repo, completionHandler: { errorMessage, url in
                // Ensure that this provider didn't say no and then try to call the completion handler
                if willProvideURL {
                    completionHandler(errorMessage, url)
                }
            })
            checked += 1
            if willProvideURL {
                break
            } else if checked >= total {
                // No providers offered an override URL for this download
                completionHandler(nil, nil)
            }
        }
    }
    
    public func repoRefresh() {
        NSLog("SileoLog: repoRefresh lock=\(lockedForInstallation) operationCount=\(operationCount()) ")
        if lockedForInstallation { return }
        let plm = PackageListManager.shared
        var reloadNeeded = false
//        if operationCount() != 0 {
//            reloadNeeded = true
//            let savedUpgrades: [(String, String)] = upgrades.map({
//                let pkg = $0.package
//                return (pkg.package, pkg.version)
//            })
//            let savedInstalls: [(String, String)] = installations.map({
//                let pkg = $0.package
//                return (pkg.package, pkg.version)
//            })
//
//            upgrades.removeAll()
//            installations.removeAll()
//            installdeps.removeAll()
//            uninstalldeps.removeAll()
//
//            for tuple in savedUpgrades {
//                let id = tuple.0
//                let version = tuple.1
//
//                if let pkg = plm.package(identifier: id, version: version) ?? plm.newestPackage(identifier: id, repoContext: nil) {
//                    if find(package: pkg) == .none {
//                        add(package: pkg, queue: .upgrades)
//                    }
//                }
//            }
//
//            for tuple in savedInstalls {
//                let id = tuple.0
//                let version = tuple.1
//
//                if let pkg = plm.package(identifier: id, version: version) ?? plm.newestPackage(identifier: id, repoContext: nil) {
//                    if find(package: pkg) == .none {
//                        add(package: pkg, queue: .installations)
//                    }
//                }
//            }
//        }
        
        // Check for essential
        var allowedHosts = [String]()
        #if targetEnvironment(macCatalyst)
        allowedHosts = ["apt.procurs.us"]
        #else
        if Jailbreak.bootstrap == .procursus {
            allowedHosts = ["apt.procurs.us", "roothide.github.io", "iosjb.top"]
        } else {
            allowedHosts = [
                "apt.bingner.com",
                "test.apt.bingner.com",
                "apt.elucubratus.com"
            ]
        }
        #endif
        let installedPackages = plm.installedPackages
        for repo in allowedHosts {
            if let repo = RepoManager.shared.repoList.first(where: { $0.url?.host == repo }) {
                for package in repo.packageArray where package.essential == "yes" &&
                                                            installedPackages[package.package] == nil &&
                                                            find(package: package) == .none {
                                                                if checkRootHide(package) {
                                                                    reloadNeeded = true
                                                                    add(package: package, queue: .installdeps)
                                                                }
                }
            }
        }
        // Don't bother to reloadData if there's nothing to reload, it's a waste of resources
        if reloadNeeded {
            reloadData(recheckPackages: true)
        }
    }
    
    public func isEssential(_ package: Package) -> Bool {
        // Check for essential
        var allowedHosts = [String]()
        #if targetEnvironment(macCatalyst)
        allowedHosts = ["apt.procurs.us"]
        #else
        if Jailbreak.bootstrap == .procursus {
            allowedHosts = ["apt.procurs.us"]
        } else {
            allowedHosts = [
                "apt.bingner.com",
                "test.apt.bingner.com",
                "apt.elucubratus.com"
            ]
        }
        #endif
        guard let sourceRepo = package.sourceRepo,
              allowedHosts.contains(sourceRepo.url?.host ?? "") else { return false }
        return package.essential == "yes"
    }
    
    private func performOperations(progressCallback: @escaping (Double, Bool, String, String) -> Void,
                                  outputCallback: @escaping (String, Int) -> Void,
                                  completionCallback: @escaping (Int, APTWrapper.FINISH, Bool) -> Void) {
        var installs = Array(self.vars.installations.raw)
        installs += self.vars.upgrades.raw
        let removals = Array(self.vars.uninstallations.raw) + Array(self.vars.uninstalldeps.raw)
        let installdeps = Array(self.vars.installdeps.raw)
        APTWrapper.performOperations(installs: installs,
                                     removals: removals,
                                     installDeps: installdeps,
                                     progressCallback: progressCallback,
                                     outputCallback: outputCallback,
                                     completionCallback: completionCallback)
    }
}

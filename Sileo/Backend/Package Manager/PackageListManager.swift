//
//  PublicListManager.swift
//  Sileo
//
//  Created by CoolStar on 7/3/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit


final class PackageListManager {
    
    static let reloadNotification = Notification.Name("SileoPackageCacheReloaded")
    static let installChange = Notification.Name("SileoInstallChanged")
    static let stateChange = Notification.Name("SileoStateChanged")
    static let prefsNotification = Notification.Name("SileoPackagePrefsChanged")
    
    private(set) var installedPackages: [String: Package] {
        didSet {
            NotificationCenter.default.post(name: RepoManager.progressNotification, object: installedPackages.count)
        }
    }
    
    public var localPackages = [String: Package]()
    
    private let initSemphaore = DispatchSemaphore(value: 0)
    public var isLoaded = false
    
//    public var allPackagesArray: [Package] {
//        var packages = [Package]()
//        var installedPackages = installedPackages
//        for repo in RepoManager.shared.repoList {
//            let repoPackageArray = repo.packageArray
//            packages += repo.packageArray
//            for package in repoPackageArray where installedPackages[package.package] != nil {
//                installedPackages.removeValue(forKey: package.package)
//            }
//        }
//        return packages + Array(installedPackages.values)
//    }
// there is no reason to include installedPackages in allPackagesArray which is used for repo package list
    public var allPackagesArray: [Package] {
        var packages = [Package]()
        for repo in RepoManager.shared.repoList {
            packages += repo.packageArray
        }
        return packages
    }

    private let databaseUpdateQueue = DispatchQueue(label: "org.coolstar.SileoStore.database-queue")
    private let packageListQueue = DispatchQueue(label: "sileo.package-list-queue")
    private let operationQueue = OperationQueue()

    public static let shared = PackageListManager()
    
    init() {
        self.installedPackages = PackageListManager.readPackages(installed: true)
        operationQueue.maxConcurrentOperationCount = (ProcessInfo.processInfo.processorCount * 2)
        
        packageListQueue.async { [self] in
            let repoMan = RepoManager.shared
            let repoList = repoMan.repoList
            
            let operations: [BlockOperation] = repoList.map { repo in
                return BlockOperation {
                    repo.packageDict = PackageListManager.readPackages(repoContext: repo)
                }
            }
            self.operationQueue.addOperations(operations, waitUntilFinished: true)
            repoMan.update(repoList)
            
            DispatchQueue.main.async {
                self.isLoaded = true
                while true {
                    if self.initSemphaore.signal() == 0 {
                        NSLog("SileoLog: PackageListManager initSemphaore.signal()")
                        break
                    }
                }
                
//                DownloadManager.aptQueue.async {
                DispatchQueue.global().async {
                    NSLog("SileoLog: DependencyResolverAccelerator.shared \(Date())")
                    let accelerator = DependencyResolverAccelerator.shared // 0.3s
                    NSLog("SileoLog: DependencyResolverAccelerator.shared \(Date())")
                    NSLog("SileoLog: DependencyResolverAccelerator.preflightInstalled() \(Date())")
                    accelerator.preflightInstalled() //2s
                    NSLog("SileoLog: DependencyResolverAccelerator.preflightInstalled() \(Date())")
                }
                
                NotificationCenter.default.post(name: PackageListManager.reloadNotification, object: nil)
                NotificationCenter.default.post(name: NewsViewController.reloadNotification, object: nil)
                
                if UserDefaults.standard.bool(forKey: "AutoRefreshSources", fallback: true) && !UserDefaults.standard.bool(forKey: "uicacheRequired") {
                    // Start a background repo refresh here instead because it doesn't like it in the Source View Controller
                    NotificationCenter.default.post(name: SourcesViewController.refreshReposNotification, object: nil)
                }
            }
        }
    }
    
    public func initWait() {
        if Thread.isMainThread {
            fatalError("\(Thread.current.threadName) cannot be used to hold backend")
        }
        if isLoaded { return }
        initSemphaore.wait()
    }
    
    public func repoInstallChange() {
        for repo in RepoManager.shared.repoList {
            repo.reloadInstalled()
        }
    }
    
    public func installChange() {
        installedPackages = PackageListManager.readPackages(installed: true)
        repoInstallChange()
    }

    public func availableUpdates() -> [(Package, Package?)] {
        var updatesAvailable: [(Package, Package?)] = []
        for package in installedPackages.values {
            guard let latestPackage = self.newestPackage(identifier: package.package, repoContext: nil) else {
                continue
            }
            
            if !checkRootHide(latestPackage) {
                continue
            }
            
            if latestPackage.version != package.version {
                if DpkgWrapper.isVersion(latestPackage.version, greaterThan: package.version) {
                    updatesAvailable.append((latestPackage, package))
                }
            }
        }
        return updatesAvailable.sorted { $0.0.name < $1.0.name }
    }

    public class func humanReadableCategory(_ rawCategory: String?) -> String {
        let category = rawCategory ?? ""
        if category.isEmpty {
            return String(localizationKey: "No_Category", type: .categories)
        }
        return String(localizationKey: category, type: .categories)
    }
    
    class func package(packageEnum: ([String: String], PackageTags)) -> Package? {
        let dictionary = packageEnum.0
        guard let packageID = dictionary["package"] else {
            return nil
        }
        guard let packageVersion = dictionary["version"] else {
            return nil
        }
        
        let package = Package(package: packageID, version: packageVersion)
        if let name = dictionary["name"] {
            package.name = name
        }
        package.icon = URL(string: dictionary["icon"])
        package.architecture = dictionary["architecture"]
        package.maintainer = Maintainer(string: dictionary["maintainer"])
        if package.maintainer != nil {
            if dictionary["author"] != nil {
                package.author = Maintainer(string: dictionary["author"])
            } else {
                package.author = package.maintainer
            }
        }
        package.rawSection = dictionary["section"]?.lowercased()
        package.section = humanReadableCategory(dictionary["section"])
        
        package.description = dictionary["description"]
        package.legacyDepiction = URL(string: dictionary["depiction"])
        package.sileoDepiction = URL(string: dictionary["sileodepiction"])
        package.nativeDepiction = URL(string: dictionary["native-depiction"])
        
        if let installedSize = dictionary["installed-size"] {
            package.installedSize = Int(installedSize)
        }

        package.tags = packageEnum.1
        if package.tags.contains(.commercial) {
            package.commercial = true
        }
        
        package.filename = dictionary["filename"]
        package.essential = dictionary["essential"]
        package.size = dictionary["size"]
        
        package.rawControl = dictionary
        return package
    }

    public class func readPackages(repoContext: Repo? = nil, packagesFile: URL? = nil, installed: Bool = false) -> [String: Package] {
        let archs = DpkgWrapper.architecture
        var tmpPackagesFile: URL?
        var toWrite: URL?
        var dict = [String: Package]()
        if installed {
            tmpPackagesFile = CommandPath.dpkgDir.appendingPathComponent("status").resolvingSymlinksInPath()
            toWrite = tmpPackagesFile
        } else if let override = packagesFile {
            tmpPackagesFile = override
            if let repo = repoContext {
                if !repo.archAvailabile {
                    return dict
                }
                toWrite = RepoManager.shared.cacheFile(named: "Packages", for: repo)
            } else {
                toWrite = override
            }
        } else if let repo = repoContext {
            if !repo.archAvailabile {
                return dict
            }
            tmpPackagesFile = RepoManager.shared.cacheFile(named: "Packages", for: repo)
            toWrite = RepoManager.shared.cacheFile(named: "Packages", for: repo)
        }
        guard let packagesFile = tmpPackagesFile,
              let rawPackagesData = try? Data(contentsOf: packagesFile) else { return dict }

        var index = 0
        var separator = "\n\n".data(using: .utf8)!
        
        guard let firstSeparator = rawPackagesData.range(of: "\n".data(using: .utf8)!, options: [], in: 0..<rawPackagesData.count) else {
            return dict
        }
        if firstSeparator.lowerBound != 0 {
            let subdata = rawPackagesData.subdata(in: firstSeparator.lowerBound-1..<firstSeparator.lowerBound)
            let character = subdata.first
            if character == 13 { // 13 means carriage return (\r, Windows line ending)
                separator = "\r\n\r\n".data(using: .utf8)!
            }
        }
        
        var savedCount = 0
        let isStatusFile = packagesFile.absoluteString.hasSuffix("status")
        while index < rawPackagesData.count {
            let newIndex: Int
            if let range = rawPackagesData.range(of: separator, options: [], in: index..<rawPackagesData.count) {
                newIndex = range.lowerBound + separator.count
            } else {
                newIndex = rawPackagesData.count
            }
            
            let subRange = index..<newIndex
            let packageData = rawPackagesData.subdata(in: subRange)
            
            index = newIndex
            
            guard let rawPackageEnum = try? ControlFileParser.dictionary(controlData: packageData, isReleaseFile: false) else {
                continue
            }
            let rawPackage = rawPackageEnum.0
            guard let packageID = rawPackage["package"] else {
                continue
            }
            
            guard !packageID.isEmpty, !packageID.hasPrefix("gsc."), !packageID.hasPrefix("cy+"), packageID != "firmware" else {
                continue
            }
            
            guard let package = self.package(packageEnum: rawPackageEnum) else {
                continue
            }
            guard archs.valid(arch: package.architecture) else {
                continue
            }
            package.sourceFile = repoContext?.rawEntry
            package.sourceFileURL = toWrite
            savedCount += packageData.count
            package.rawData = packageData
            
            package.fromStatusFile = isStatusFile
            
            if isStatusFile {
                var wantInfo: pkgwant = .install
                var eFlag: pkgeflag = .ok
                var pkgStatus: pkgstatus = .installed
            
                let statusValid = DpkgWrapper.getValues(statusField: package.rawControl["status"],
                                                        wantInfo: &wantInfo,
                                                        eFlag: &eFlag,
                                                        pkgStatus: &pkgStatus)
                if !statusValid {
                    continue
                }
            
                package.wantInfo = wantInfo
                package.eFlag = eFlag
                package.status = pkgStatus
            
                if package.eFlag == .ok {
                    if package.status == .notinstalled || package.status == .configfiles {
                        continue
                    }
                }
                let packageInstallPath = CommandPath.dpkgDir.appendingPathComponent("info/\(packageID).list")
                let attr = try? FileManager.default.attributesOfItem(atPath: packageInstallPath.path)
                package.installDate = attr?[FileAttributeKey.modificationDate] as? Date
                dict[package.package] = package
            } else {
                if let otherPkg = dict[packageID] {
                    //if DpkgWrapper.isVersion(package.version, greaterThan: otherPkg.version) {
                    if preferredPackage(old: otherPkg, new: package) {
                        if package.architecture==otherPkg.architecture {
                            package.addOld(from: otherPkg)
                        }
                        dict[packageID] = package
                    } else {
                        if package.architecture==otherPkg.architecture {
                            otherPkg.addOld(from: package)
                        }
                    }
                } else {
                    dict[packageID] = package
                }
            }
        }

        return dict
    }

    public func packageList(identifier: String = "", search: String? = nil, sortPackages sort: Bool = false, repoContext: Repo? = nil, lookupTable: [String: [Package]]? = nil, packagePrepend: [Package]? = nil) -> [Package] {
        NSLog("SileoLog: packageList=\(identifier),\(search),\(sort),\(repoContext),\(lookupTable?.count),\(packagePrepend) : \(lookupTable?.map({ ($0,$1.count) }))")
        var packageList = [Package]()
        if identifier == "--installed" {
            packageList = Array(installedPackages.values)
        } else if identifier == "--wishlist" {
            packageList = packages(identifiers: WishListManager.shared.wishlist, sorted: sort)
        } else if let prepend = packagePrepend {
            packageList = prepend
        } else {
            if var search = search?.lowercased(),
               let lookupTable = lookupTable {
                var isFound = false
                while !search.isEmpty && !isFound {
                    if let packages = lookupTable[search] {
                        packageList = packages
                        isFound = true
                    } else {
                        search.removeLast()
                    }
                }
                if !isFound {
                    packageList = repoContext?.packageArray ?? allPackagesArray
                }
            } else {
                packageList = repoContext?.packageArray ?? allPackagesArray
            }
        }
        
        if identifier=="--contextInstalled" {
            packageList = packageList.filter({ installedPackages.keys.contains($0.package) })
        } else if identifier=="--contextRootHide" {
            packageList = packageList.filter({ $0.architecture == DpkgWrapper.architecture.primary.rawValue })
        } else if identifier.hasPrefix("category:") {
            let index = identifier.index(identifier.startIndex, offsetBy: 9)
            let category = PackageListManager.humanReadableCategory(String(identifier[index...]))
            packageList = packageList.filter({ $0.section == category })
        } else if identifier.hasPrefix("author:") {
            let index = identifier.index(identifier.startIndex, offsetBy: 7)
            let name = String(identifier[index...])
            packageList = packageList.filter {
                guard let authorName = $0.author?.name else {
                    return false
                }
                return authorName == name
            }
        }
        
        if let searchQuery = search, !searchQuery.isEmpty {
            let lowercased = searchQuery.lowercased()
            packageList.removeAll { package in
                // check if the user search term is in the package ID, description or in the author / maintainer name
//                var fields = [package.package, package.name, package.author?.name, package.maintainer?.name]
                var fields = [package.package, package.name, package.description]
                for field in fields {
                    if let field = field, field.count>0 {
                        if field.localizedStandardContains(lowercased) {
                            return false
                        }
                    }
                }
                return true
            }
            
            if searchQuery.lengthOfBytes(using: String.Encoding.utf8) < 2 && packageList.count > 1000 {
                //skip sort
                return packageList
            }
        }
        
//        for p in packageList {
//            NSLog("SileoLog: packageList=\(p.package) \(p.architecture) \(p.version) \(p.sourceRepo) \(p.sourceRepo?.displayName) \(p.sourceFile) author:\(p.author?.string)")
//        }
        // Remove Any Duplicates
//        var temp = [String: Package]()
//        for package in packageList {
//            if let existing = temp[package.package] {
//                if preferredPackage(old:existing, new:package) {
//                    temp[package.package] = package
//                }
//            } else {
//                temp[package.package] = package
//            }
//        }
//        packageList = Array(temp.values)
        
        if sort {
            packageList = sortPackages(packages: packageList, search: search)
        }
//        for p in packageList {
//            NSLog("SileoLog: packageList2=\(p.package) \(p.architecture) \(p.version) \(p.sourceRepo) \(p.sourceRepo?.displayName) \(p.sourceFile)")
//        }
        return packageList
    }
    
    public func sortPackages(packages: [Package], search: String?) -> [Package] {
        var starttimes = timespec(tv_sec: 0, tv_nsec: 0)
        clock_gettime(CLOCK_REALTIME, &starttimes)
        defer {
            var endtimes = timespec(tv_sec: 0, tv_nsec: 0)
            clock_gettime(CLOCK_REALTIME, &endtimes)
            
            let startMillis = UInt64(starttimes.tv_sec) * 1000 + UInt64(starttimes.tv_nsec) / 1_000_000
            let endMillis = UInt64(endtimes.tv_sec) * 1000 + UInt64(endtimes.tv_nsec) / 1_000_000
            let timesinterval = Double((endMillis - startMillis)) / 1000
            
            NSLog("SileoLog: sortPackages(\(packages.count)) cost \(timesinterval) for \(search)")
//            Thread.callStackSymbols.forEach{NSLog("SileoLog: sortPackages callstack=\($0)")}
        }

        var tmp = packages
        tmp.sort { package1, package2 -> Bool in
            
            var check1: Bool
            var check2: Bool
                
            if let searchQuery = search?.lowercased(), !searchQuery.isEmpty
            {
                let name1 = package1.name.lowercased()
                let name2 = package2.name.lowercased()
                
                check1 = name1.hasPrefix(searchQuery)
                check2 = name2.hasPrefix(searchQuery)
                
                if check1 && !check2 {
                    return true
                } else if !check1 && check2 {
                    return false
                }
                
                check1 = name1.contains(searchQuery)
                check2 = name2.contains(searchQuery)
                
                if check1 && !check2 {
                    return true
                } else if !check1 && check2 {
                    return false
                }
                
                check1 = checkRootHide(package1)
                check2 = checkRootHide(package2)
                
                if check1 && !check2 {
                    return true
                } else if !check1 && check2 {
                    return false
                }
                
                if package1.package == package2.package {
                    return DpkgWrapper.isVersion(package1.version, greaterThan: package2.version)
                }
                
                return name1.compare(name2) != .orderedDescending
                
            } else {
                
                check1 = checkRootHide(package1)
                check2 = checkRootHide(package2)
                
                if check1 && !check2 {
                    return true
                } else if !check1 && check2 {
                    return false
                }
                
                if package1.package == package2.package {
                    return DpkgWrapper.isVersion(package1.version, greaterThan: package2.version)
                }
                
                let name1 = package1.name.lowercased()
                let name2 = package2.name.lowercased()
                return name1.compare(name2) != .orderedDescending
            }
        }
        return tmp
    }
    
    public func newestPackage(identifier: String, repoContext: Repo?=nil, packages: [Package]? = nil) -> Package? {
        if let repoContext = repoContext {
            return repoContext.packageDict[identifier.lowercased()]
        } else {
            var newestPackage: Package?
            if var packages = packages {
                packages = packages.filter { $0.package == identifier }
                for package in packages {
                    if let old = newestPackage {
                        if preferredPackage(old: old, new: package) {
                            newestPackage = package
                        }
                    } else {
                        newestPackage = package
                    }
                }
                return newestPackage
            }
            for repo in RepoManager.shared.repoList {
                if let package = repo.packageDict[identifier] {
                    if let old = newestPackage {
                        if preferredPackage(old: old, new: package) {
                            newestPackage = package
                        }
                    } else {
                        newestPackage = package
                    }
                }
            }
            return newestPackage
        }
    }
    
    public func installedPackage(identifier: String) -> Package? {
        installedPackages[identifier.lowercased()]
    }
    
    public func package(url: URL) -> Package? {
        guard let rawPackageControl = try? DpkgWrapper.rawFields(packageURL: url) else {
            return nil
        }
        guard let rawPackage = try? ControlFileParser.dictionary(controlFile: rawPackageControl, isReleaseFile: true) else {
            return nil
        }
        guard let package = PackageListManager.package(packageEnum: rawPackage) else {
            return nil
        }
        package.local_deb = url.path
        localPackages[package.package] = package
        return package
    }
    
    public func packages(identifiers: [String], sorted: Bool, repoContext: Repo? = nil, packages: [Package]? = nil) -> [Package] {
        if identifiers.isEmpty { return [] }
        var rawPackages = [Package]()
        if let packages = (repoContext?.packageArray ?? packages) {
            for identifier in identifiers {
                rawPackages += packages.filter { $0.package == identifier }
                //why need local packages if we use repo or packages array
//                if let package = localPackages[identifier] {
//                    rawPackages.append(package)
//                }
            }
            
            if sorted {
                return Array(Set(rawPackages.sorted(by: { pkg1, pkg2 -> Bool in
                    return pkg1.name.compare(pkg2.name) != .orderedDescending
                })))
            } else {
                return Array(Set(rawPackages))
            }
        } else {
            return identifiers.compactMap { newestPackage(identifier: $0, repoContext: nil) }
        }
    }
    
    public func package(identifier: String, version: String, packages: [Package]? = nil) -> Package? {
        if let packages = packages {
            return packages.first(where: { $0.package == identifier && $0.version == version })
        }
        
        //prefer using local packages
        if let package = localPackages[identifier],
           let version = package.getVersion(version) {
            return version
        }
        
        for repo in RepoManager.shared.repoList {
            if let package = repo.packageDict[identifier],
               let version = package.getVersion(version) {
                return version
            }
        }
        return nil
    }

    public func upgradeAll() {
        self.upgradeAll(completion: nil)
    }
    
    public func upgradeAll(completion: (() -> Void)?) {
        let packagePairs = self.availableUpdates()
        let updatesNotIgnored = packagePairs.filter({ $0.1?.wantInfo != .hold })
        if updatesNotIgnored.isEmpty {
            completion?()
            return
        }

        var upgrades = Set<Package>()
        
        var incompatible = false
        
        for packagePair in updatesNotIgnored {
            let newestPkg = packagePair.0
            
            if let installedPkg = packagePair.1, installedPkg == newestPkg {
                continue
            }
            
            if checkRootHide(newestPkg) {
                upgrades.insert(newestPkg)
            } else {
                incompatible = true
            }
        }
        
        if incompatible && upgrades.count==0 {
            DispatchQueue.main.async {
                
                completion?()
                
                let alert = UIAlertController(title: "", message: "No RootHide Package(s)", preferredStyle: .alert)
                
                let okAction = UIAlertAction(title: String(localizationKey: "OK"), style: .default) { _ in
                    alert.dismiss(animated: true, completion: nil)
                }
                alert.addAction(okAction)
                
                SileoAppDelegate.presentController(alert)
            }
            return
        }
        
        DownloadManager.shared.upgradeAll(packages: upgrades) {
            DownloadManager.shared.reloadData(recheckPackages: true) {
                completion?()
                if UserDefaults.standard.bool(forKey: "UpgradeAllAutoQueue", fallback: true) {
                    TabBarController.singleton?.presentPopupController()
                }
            }
        }
    }
}


func preferredPackage(old: Package, new: Package) -> Bool {
    if Bootstrap.roothide {
        let dpkgArch = DpkgWrapper.architecture.primary.rawValue
        let preferredNew = (new.architecture==dpkgArch ?1:0) + (new.architecture=="all" ?1:0) + (new.sourceRepo?.preferredArch==dpkgArch ?1:0)
        let preferredOld = (old.architecture==dpkgArch ?1:0) + (old.architecture=="all" ?1:0) + (old.sourceRepo?.preferredArch==dpkgArch ?1:0)
        if preferredNew==preferredOld {
            if DpkgWrapper.isVersion(new.version, greaterThan: old.version) {
                return true
            }
        } else if preferredNew > preferredOld {
            return true;
        }
    } else if DpkgWrapper.isVersion(new.version, greaterThan: old.version) {
        return true;
    }
    
    return false
}


func checkRootHide(_ package: Package) -> Bool {

//        NSLog("SileoLog: package.rawControl=\(package.rawControl)")
//        var found=false
//        if let depends = package.rawControl["depends"] {
//            let parts = depends.components(separatedBy: CharacterSet(charactersIn: ",|"))
//            for part in parts {
//                let newPart = part.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression).replacingOccurrences(of: " ", with: "")
//                if newPart=="roothide" {
//                    found = true
//                }
//            }
//        }
//        return found
    
    //NSLog("SileoLog: checkRootHide=\(package.package)(\(package.architecture)):\(package.sourceRepo), \(package.sourceRepo?.repoName), \(package.sourceRepo?.displayName), \(package.sourceRepo?.rawURL), \(package.sourceRepo?.displayURL), \(package.sourceRepo?.repoURL)")
    
    let roothideArch = DPKGArchitecture.Architecture.roothide.rawValue
    
    if package.architecture==roothideArch {
        return true;
    }
    
    if package.architecture=="all" {
        if package.sourceRepo==nil { //local deb ?
            return true
        }
        
        if package.sourceRepo?.preferredArch==roothideArch {
            return true
        }
    }
    
    return false;
}

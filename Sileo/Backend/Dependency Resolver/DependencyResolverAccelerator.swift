//
//  DependencyResolverAccelerator.swift
//  Sileo
//
//  Created by CoolStar on 1/19/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

class DependencyResolverAccelerator {
    public static let shared = DependencyResolverAccelerator()
    
    struct PreflightedPackage: PackageProtocol {

        let version: String
        let package: String
        let data: Data
        
        init(package: Package) {
            self.version = package.version
            self.package = package.package
            self.data = package.rawData ?? Data()
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(package)
            hasher.combine(version)
        }
    }
    
    private var preflightedPackages: [URL: Set<PreflightedPackage>] = [:]
    private var toBePreflighted: [URL: Set<PreflightedPackage>] = [:]
    private var preflightLock = NSRecursiveLock()
    public func preflightInstalled() {
        NSLog("SileoLog: DependencyResolverAccelerator.preflightInstalled()")
        if Thread.isMainThread {
            fatalError("Don't call things that will block the UI from the main thread")
        }
       
        preflightLock.lock()
        try? getDependencies(packages: Array(PackageListManager.shared.installedPackages.values))
        preflightLock.unlock()
    }
    
    private var depResolverPrefix: URL = {
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        let listsURL = FileManager.default.documentDirectory.appendingPathComponent("sileolists")
        if !listsURL.dirExists {
            try? FileManager.default.createDirectory(at: listsURL, withIntermediateDirectories: true)
        }
        return listsURL
        #else
        return URL(fileURLWithPath: CommandPath.sileolists)
        #endif
    }()
    
    init() {
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        try? FileManager.default.removeItem(atPath: CommandPath.sileolists)
        #else
        spawnAsRoot(args: [CommandPath.rm, "-rf", rootfs(CommandPath.sileolists)])
        spawnAsRoot(args: [CommandPath.mkdir, "-p", rootfs(CommandPath.sileolists)])
        spawnAsRoot(args: [CommandPath.chown, "-R", CommandPath.group, rootfs(CommandPath.sileolists)])
        spawnAsRoot(args: [CommandPath.chmod, "-R", "0755", rootfs(CommandPath.sileolists)])
        #endif
    }
    
    public func removeRepo(repo: Repo) {
        NSLog("SileoLog: DependencyResolverAccelerator.removeRepo(\(repo.url)")
        if !repo.archAvailabile {
            return
        }
        
        self.preflightLock.lock()
        defer { self.preflightLock.unlock() }
        
        let url = RepoManager.shared.cacheFile(named: "Packages", for: repo)
        let newSourcesFile = depResolverPrefix.appendingPathComponent(url.lastPathComponent)
        toBePreflighted.removeValue(forKey: url)
        preflightedPackages.removeValue(forKey: url)
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        try? FileManager.default.removeItem(at: newSourcesFile)
        #else
        spawnAsRoot(args: [CommandPath.rm, "-rf", rootfs(newSourcesFile.path)])
        #endif
    }
    
    public func buildOperations(packages: [Package]) {
        let cachedirpath = jbroot("\(CommandPath.sileolists)/operations")
        let resolverPrefix = URL(fileURLWithPath: cachedirpath)
        
        spawnAsRoot(args: [CommandPath.rm, "-rf", rootfs(cachedirpath)])
        
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755,
            .ownerAccountID: 501,
            .groupOwnerAccountID: 501
        ]
        
        try! FileManager.default.createDirectory(atPath: cachedirpath, withIntermediateDirectories: false, attributes: attributes)
        
        for package in packages {
            //NSLog("SileoLog: sourcesFile=\(sourcesFile) packages=\(packages.map({ $0.package }))")
            
            guard let data=package.rawData, let sourceFile=package.sourceFileURL else { continue }
            
            let newSourcesFile = resolverPrefix.appendingPathComponent(sourceFile.lastPathComponent)
            
            var sourcesData = Data()
            var bytes = [UInt8](data)
            if bytes.suffix(2) != [10, 10] { // \n\n
                if bytes.last == 10 {
                    bytes.append(10)
                } else {
                    bytes.append(contentsOf: [10, 10])
                }
            }
            sourcesData.append(Data(bytes))
            try! sourcesData.append(to: newSourcesFile)
        }
    }
    
    public func getDependencies(packages: [Package]) throws {
        NSLog("SileoLog: DependencyResolverAccelerator.getDependencies(\(packages.map({ $0.package }))")
        NSLog("SileoLog: preflightedPackages=\(preflightedPackages.keys)")
        NSLog("SileoLog: toBePreflighted=\(toBePreflighted.keys))")
        if Thread.isMainThread {
            fatalError("Don't call things that will block the UI from the main thread")
        }
        PackageListManager.shared.initWait()
        NSLog("SileoLog: getDependencies2")
        
        self.preflightLock.lock()
        defer { self.preflightLock.unlock() }

        for package in packages {
            getDependenciesInternal(package: package)
        }
        NSLog("SileoLog: getDependencies3 toBePreflighted=\(toBePreflighted.keys))")
        
        let resolverPrefix = depResolverPrefix
        for (sourcesFile, packages) in toBePreflighted {
            //NSLog("SileoLog: sourcesFile=\(sourcesFile) packages=\(packages.map({ $0.package }))")
            
            defer { toBePreflighted.removeValue(forKey: sourcesFile) }
            
            if sourcesFile.lastPathComponent == "status" || sourcesFile.scheme == "local" {
                continue
            }
            let newSourcesFile = resolverPrefix.appendingPathComponent(sourcesFile.lastPathComponent)
            
            var sourcesData = Data()
            for package in packages {
                var bytes = [UInt8](package.data)
                if bytes.suffix(2) != [10, 10] { // \n\n
                    if bytes.last == 10 {
                        bytes.append(10)
                    } else {
                        bytes.append(contentsOf: [10, 10])
                    }
                }
                sourcesData.append(Data(bytes))
            }
            do {
                try sourcesData.append(to: newSourcesFile)
            } catch {
                NSLog("SileoLog: throw \(error)")
                throw error
            }
            
            let preflighted = preflightedPackages[sourcesFile] ?? Set<PreflightedPackage>()
            preflightedPackages[sourcesFile] = preflighted.union(packages)
        }
        NSLog("SileoLog: getDependencies4")
    }
    
    private func getDependenciesInternal(package: Package) {
        //NSLog("SileoLog: getDependenciesInternal \(package.package) \(package.sourceFileURL)")
        let url = package.sourceFileURL ?? URL(string: "local://")!
        if let preflighted = preflightedPackages[url] {
            if preflighted.contains(where: { $0 == package }) {
                return
            }
        }
        for packageVersion in package.allVersions() {
            getDependenciesInternal2(package: packageVersion, sourceFileURL: url)
        }
    }
   
    private func getDependenciesInternal2(package: Package, sourceFileURL: URL) {
        //NSLog("SileoLog: getDependenciesInternal2 \(package.package) \(sourceFileURL)")
        if let preflighted = toBePreflighted[sourceFileURL] {
            if preflighted.contains(where: { $0 == package }) {
                return
            }
        } else {
            toBePreflighted[sourceFileURL] = Set<PreflightedPackage>()
        }
        toBePreflighted[sourceFileURL]?.insert(PreflightedPackage(package: package))
        
        //also resolve the installed package itself
        //,but this doesn't make sense due the package is in an inconsistent state and dpkg cannot uninstall it
//        for repo in RepoManager.shared.repoList {
//            if let thePackage = repo.newestPackage(identifier: package.package) {
//                getDependenciesInternal(package: thePackage)
//            }
//        }
  
        // Depends, Pre-Depends, Recommends, Suggests, Breaks, Conflicts, Provides, Replaces, Enhance
        let packageKeys = ["depends", "pre-depends", "conflicts", "replaces", "recommends", "provides", "breaks"]
        for packageKey in packageKeys {
            if let packagesData = package.rawControl[packageKey] {
                let packageIds = parseDependsString(depends: packagesData)
                for repo in RepoManager.shared.repoList {
                    for packageID in packageIds {
                        if let depPackage = repo.newestPackage(identifier: packageID) {
                            getDependenciesInternal(package: depPackage)
                        }
                    }
                    
                    for depPackage in repo.packagesProvides {
                        for packageId in packageIds {
                            if depPackage.rawControl["provides"]?.contains(packageId) ?? false {
                                getDependenciesInternal(package: depPackage)
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func parseDependsString(depends: String) -> [String] {
        let parts = depends.components(separatedBy: CharacterSet(charactersIn: ",|"))
        var packageIds: [String] = []
        for part in parts {
            let newPart = part.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression).replacingOccurrences(of: " ", with: "")
            packageIds.append(newPart)
        }
        return packageIds
    }
    
}

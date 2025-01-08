//
//  CanisterResolver.swift
//  Sileo
//
//  Created by Amy on 23/03/2021.
//  Copyright © 2021 Amy While. All rights reserved.
//

import UIKit
// import DepictionKit
import Evander
import ZippyJSON

final class CanisterResolver {
    
    public static let nistercanQueue = DispatchQueue(label: "Sileo.NisterCan", qos: .userInteractive)
    public static let shared = CanisterResolver()
    public var packages = SafeArray<ProvisionalPackage>(queue: canisterQueue, key: queueKey, context: queueContext)
    private var cachedQueue = SafeArray<Package>(queue: canisterQueue, key: queueKey, context: queueContext)
    private var savedSearch = [String]()
    
    static let canisterQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Sileo.CanisterQueue", qos: .userInitiated)
        queue.setSpecific(key: CanisterResolver.queueKey, value: CanisterResolver.queueContext)
        return queue
    }()
    public static let queueKey = DispatchSpecificKey<Int>()
    public static var queueContext = 50
    
    @discardableResult public func fetch(_ query: String, fetch: ((Bool) -> Void)? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        fetch?(false); return false
        #endif
        guard UserDefaults.standard.bool(forKey: "ShowProvisional", fallback: true) else { fetch?(false); return false }
        guard query.lengthOfBytes(using: String.Encoding.utf8) >= 2,
           !savedSearch.contains(query),
           let formatted = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { fetch?(false); return false }
        let url = "https://api.canister.me/v2/jailbreak/package/search?limit=250&q=\(formatted)"
        EvanderNetworking.request(url: url, type: Data.self, cache: .init(localCache: false)) { [self] success, _, _, data in
            NSLog("SileoLog: CanisterResolver.fetch \(query): \(success),\(data)")
            
            guard success, let data else {
                return
            }
                        
            do {
                let response = try ZippyJSONDecoder().decode(PackageSearchResponse.self, from: data)
                
                self.savedSearch.append(query)
                var change = false
                for package in response.data ?? [] {
                    if !self.packages.contains(where: { $0.package == package.package })
                        && package.repository.isBootstrap==false //the suite of bootstrap repo may not match the current device, so we have to ignore it
                        && DpkgWrapper.architecture.valid(arch: package.architecture)
                    {
                        change = true
                        self.packages.append(package)
                        NSLog("SileoLog: CanisterResolver new package: \(package.package) \(package.repository.uri)")
                    }
                }
                NSLog("SileoLog: CanisterResolver.packages: \(self.packages.count)")
                fetch?(change)
                
            } catch {
                NSLog("SileoLog: JSONDecoder err=\(error)")
                return
            }
        }
        return true
    }
    
    @discardableResult public func batchFetch(_ packages: [String], fetch: ((Bool) -> Void)? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        fetch?(false); return false
        #endif
        var packages = packages
        for package in packages {
            if savedSearch.contains(package) {
                packages.removeAll { package == $0 }
            }
        }
        if packages.isEmpty { fetch?(false); return false }
        let identifiers = packages.joined(separator: ",")
        NSLog("SileoLog: CanisterResolver.batchFetch identifiers=\(identifiers)")
        guard let formatted = identifiers.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { fetch?(false); return false }
        let url = "https://api.canister.me/v2/jailbreak/package/multi?ids=\(formatted)"
        EvanderNetworking.request(url: url, type: Data.self, cache: .init(localCache: false)) { [self] success, _, _, data in
            guard success, let data else {
                return
            }
            do {
                let response = try ZippyJSONDecoder().decode(PackageSearchResponse.self, from: data)
                self.savedSearch += packages
                var change = false
                for package in response.data ?? [] {
                    NSLog("SileoLog: CanisterResolver batch package: \(package.package) \(package.repository.uri)")
                    if !self.packages.contains(where: { $0.package == package.package })
                        && package.repository.isBootstrap == false
                        && DpkgWrapper.architecture.valid(arch: package.architecture)
                    {
                        change = true
                        self.packages.append(package)
                        NSLog("SileoLog: CanisterResolver new package: \(package.package) \(package.repository.uri)")
                    }
                }
                fetch?(change)
            } catch {
                NSLog("SileoLog: JSONDecoder err=\(error)")
            }
        }
        return true
    }
    
    class public func piracy(_ urls: [URL], response: @escaping (_ safe: [URL], _ piracy: [URL]) -> Void) {
        var url = "https://api.canister.me/v2/jailbreak/repository/safety?uris="
        for (index, url2) in urls.enumerated() {
            let suffix = (index == urls.count - 1) ? "" : ","
            url += (url2.absoluteString  + suffix)
        }
        EvanderNetworking.request(url: url, type: [String: Any].self, cache: .init(localCache: false)) { success, _, _, dict in
            guard success,
                  let dict = dict,
                  let data = dict["data"] as? [[String: Any]] else {
                return response(urls, [URL]())
            }
            var safe = [URL]()
            var piracy = [URL]()
            for repo in data {
                guard let repoURI = repo["uri"] as? String,
                      let url3 = URL(string: repoURI) else {
                    continue
                }
                if repo["safe"] as? Bool == true {
                    safe.append(url3)
                } else {
                    piracy.append(url3)
                }
            }
            return response(safe, piracy)
        }
    }
    
    public func queuePackage(_ package: Package) {
        NSLog("SileoLog: CanisterResolver.queuePackage \(package.package) \(package.architecture) \(package.source?.uri)")
        
        assert((package.isProvisional ?? false))
        
        cachedQueue.removeAll { $0.package == package.package }
        cachedQueue.append(package)
    }
    
    public func queueCache() {
        NSLog("SileoLog: CanisterResolver.queueCache total=\(cachedQueue.count)")
        
        if DownloadManager.shared.queueRunning { return }

        var refreshLists = false
        for (index, package) in cachedQueue.enumerated().reversed() {
            NSLog("SileoLog: CanisterResolver.queueCache package[\(index)] \(package) \(package.source?.uri)")
            let source = package.source!
            if let repo = RepoManager.shared.repo(with: source.uri, suite: source.suite, components: source.component?.components(separatedBy: .whitespaces)),
               let pkg = PackageListManager.shared.newestPackage(identifier: package.package, repoContext: repo) {
                
                if checkRootHide(pkg) {
                    let queueFound = DownloadManager.shared.find(package: pkg)
                    if queueFound == .none {
                        DownloadManager.shared.add(package: pkg, queue: .installations)
                        refreshLists = true
                    }
                    self.cachedQueue.removeAll(where: { $0.package == package.package })
                } else {
                    self.cachedQueue.removeAll(where: { $0 == package })
                }
                
//                self.packages.removeAll(where: { $0.package == package.package })
            }
        }
        if refreshLists {
            NotificationCenter.default.post(name: CanisterResolver.refreshList, object: nil)
            DownloadManager.shared.reloadData(recheckPackages: true)
        }
    }
    
    public class func package(_ provisional: ProvisionalPackage) -> Package? {
        let package = Package(package: provisional.package, version: provisional.version)
        package.name = provisional.name ?? provisional.package
        package.source = provisional.repository
        if let url = URL(string: provisional.icon) {
            package.icon = url
        }
        package.description = provisional.description
        package.author = provisional.author
        package.sileoDepiction = provisional.sileoDepiction
        package.isProvisional = true
        package.rawSection = provisional.section
        package.section = PackageListManager.humanReadableCategory(package.rawSection)
        return package
    }
    
    public func package(for bundleID: String) -> Package? {
        
        let temp = packages.filter { $0.package == bundleID }
        var buffer: Package?
        for provis in temp {
            guard let package = CanisterResolver.package(provis) else { continue }
            if let contained = buffer {
                if package > contained {
                    buffer = package
                }
            } else {
                buffer = package
            }
        }
        return buffer
    }
    
    private struct IngestPackage: Codable {
        
        let package_id: String
        let package_version: String
        let package_author: String?
        let package_maintainer: String?
        let repository_uri: String?
        
        init(package: Package) {
            self.package_id = package.package
            self.package_version = package.version
            self.package_author = package.author?.string
            self.package_maintainer = package.maintainer?.string
            self.repository_uri = package.sourceRepo?.displayURL ?? "file:///var/lib/dpkg/status"
        }
        
    }
    
    public func ingest(packages: [Package]) {
        print("Ingesating?")
        guard !packages.isEmpty else {
            return
        }
        var toIngest = [IngestPackage]()
        toIngest.reserveCapacity(packages.count)
        for package in packages {
            toIngest.append(.init(package: package))
        }
        
        guard let data = try? JSONEncoder().encode(toIngest) else {
            return
        }

        let url = URL(string: "https://api.canister.me/v2/jailbreak/download/ingest")!
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        urlRequest.httpMethod = "POST"
        for (key, value) in UIDevice.current.headers {
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = data
        
        NSLog("SileoLog: ingest request: \(UIDevice.current.headers)")
        NSLog("SileoLog: ingest body: \(String(data: data, encoding: String.Encoding.utf8))")
        EvanderNetworking.request(request: urlRequest, type: [String: Any].self) { success, statusCode, error, returnData in
            NSLog("SileoLog: ingest response: \(success),\(statusCode),\(error),\(returnData)")
        }
         
    }
    
    static let refreshList = Notification.Name("Canister.RefreshList")
}

struct ProvisionalPackage: PackageProtocol, Decodable {
    
    static func ==(lhs: ProvisionalPackage, rhs: ProvisionalPackage) -> Bool {
        lhs.package == rhs.package && lhs.version == rhs.version
    }
    
    let package: String
    let version: String
    let name: String?
    let maintainer: Maintainer?
    let author: Maintainer?
    let architecture: DPKGArchitecture.Architecture?
    let section: String?
    let description: String?
    
    let icon: String?
    let sileoDepiction: URL?
    let header: URL?
    
    let repository: ProvisionalRepo

    public var defaultIcon: UIImage {
        if let section = section {
            // we have to do this because some repos have various Addons sections
            // ie, Addons (activator), Addons (youtube), etc
            if section.lowercased().contains("addons") {
                return UIImage(named: "Category_addons") ?? UIImage(named: "Category_tweak")!
            } else if section.lowercased().contains("themes") {
                // same case for themes
                return UIImage(named: "Category_themes") ?? UIImage(named: "Category_tweak")!
            }
            
            return UIImage(named: "Category_\(section.lowercased())") ?? UIImage(named: "Category_tweak")!
        }
        return UIImage(named: "Category_tweak")!
    }
    
}

struct ProvisionalRepo: Decodable, Equatable, Hashable {
    
    let uri: URL
    let suite: String
    let component: String?
    
    let name: String?
    let slug: String
    let tier: Int
    
    let isBootstrap: Bool
    
    static func ==(lhs: ProvisionalRepo, rhs: ProvisionalRepo) -> Bool {
        lhs.slug == rhs.slug
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }
    
}

struct PackageSearchResponse: Decodable {
    
    let message: String?
    let count: UInt
    let data: [ProvisionalPackage]?
    let error: String?
    
}

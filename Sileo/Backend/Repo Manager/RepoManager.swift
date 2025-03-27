//
//  RepoManager.swift
//  Sileo
//
//  Created by Kabir Oberai on 11/07/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit
import Evander

// swiftlint:disable:next type_body_length
final class RepoManager {
    
    private let NO_PGP = true
    private var hasDuplicateRepo = false
    
    static let progressNotification = Notification.Name("SileoRepoManagerProgress")
    private var repoDatabase = DispatchQueue(label: "org.coolstar.SileoStore.repo-database")

    enum RepoHashType: String, CaseIterable {
        case sha256
        case sha512

        var hashType: HashType {
            switch self {
            case .sha256: return .sha256
            case .sha512: return .sha512
            }
        }
    }

    static let shared = RepoManager()

    private(set) var repoList: [Repo] = []
    private var repoListLock = DispatchSemaphore(value: 1)
    
    public func sortedRepoList(repos: [Repo]?=nil) -> [Repo] {
        let repos = repos ?? repoList
        return repos.sorted(by: { obj1, obj2 -> Bool in
            return obj1.repoName.localizedCaseInsensitiveCompare(obj2.repoName) == .orderedAscending
        })
    }

    public func update(_ repo: Repo) {
        repoDatabase.async(flags: .barrier) {
            repo.releaseProgress = 0
            repo.packagesProgress = 0
            repo.releaseGPGProgress = 0
            repo.startedRefresh = false
        }
    }

    public func update(_ repos: [Repo]) {
        repoDatabase.sync(flags: .barrier) {
            for repo in repos {
                repo.releaseProgress = 0
                repo.packagesProgress = 0
                repo.releaseGPGProgress = 0
                repo.startedRefresh = false
            }
        }
    }

    // swiftlint:disable:next force_try
    lazy private var dataDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    #if targetEnvironment(simulator) || TARGET_SANDBOX
    private var sourcesURL: URL {
        FileManager.default.documentDirectory.appendingPathComponent("sileo.sources")
    }
    #endif

    init() {
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        parseSourcesFile(at: sourcesURL)
        #else
        fixLists()
        let directory = URL(fileURLWithPath: CommandPath.sourcesListD)
        let alternative = URL(fileURLWithPath: CommandPath.alternativeSources)
        for item in (directory.implicitContents + alternative.implicitContents)  {
            if item.pathExtension == "list" {
                parseListFile(at: item)
            } else if item.pathExtension == "sources" {
                self.hasDuplicateRepo = false
                parseSourcesFile(at: item)
                if self.hasDuplicateRepo && item.path.hasSuffix("/etc/apt/sources.list.d/sileo.sources") {
                    self.writeListToFile()
                }
            }
        }
        #endif
        if !UserDefaults.standard.bool(forKey: "Sileo.DefaultRepo") {
            UserDefaults.standard.set(true, forKey: "Sileo.DefaultRepo")
            addRepos(with: [
                URL(string: "https://yourepo.com")!,
                URL(string: "https://havoc.app")!,
                URL(string: "https://repo.chariz.com")!,
            ])
        }
    }
    
    private func normalizeURL(_ url: URL) -> URL? {
        var normalizedStr = url.absoluteString
        if normalizedStr.last != "/" {
            normalizedStr.append("/")
        }
        return URL(string: normalizedStr)
    }

    @discardableResult func addRepos(with urls: [URL]) -> [Repo] {
        var repos = [Repo]()
        func handleDistRepo(_ url: URL) -> Bool {
            let host = url.host?.lowercased()
            switch host {
            case "apt.bigboss.org", "apt.thebigboss.org", "thebigboss.org", "bigboss.org":
                let bigBoss = Repo()
                bigBoss.rawURL = "http://apt.thebigboss.org/repofiles/cydia/"
                bigBoss.suite = "stable"
                bigBoss.components = ["main"]
                bigBoss.rawEntry = """
                Types: deb
                URIs: http://apt.thebigboss.org/repofiles/cydia/
                Suites: stable
                Components: main
                """
                bigBoss.entryFile = "\(CommandPath.sourcesListD)/sileo.sources"
                repoList.append(bigBoss)
                repos.append(bigBoss)
                return true
            case "apt.procurs.us":
                let arch = DpkgWrapper.architecture
                let suite = arch.primary == .rootful ? "iphoneos-arm64/":""
                let jailbreakRepo = Repo()
                jailbreakRepo.rawURL = "https://apt.procurs.us/"
                jailbreakRepo.suite = "\(suite)\(UIDevice.current.cfMajorVersion)"
                jailbreakRepo.components = ["main"]
                jailbreakRepo.rawEntry = """
                Types: deb
                URIs: https://apt.procurs.us/
                Suites: \(suite)\(UIDevice.current.cfMajorVersion)
                Components: main
                """
                jailbreakRepo.entryFile = "\(CommandPath.sourcesListD)/procursus.sources"
                repoList.append(jailbreakRepo)
                repos.append(jailbreakRepo)
                return true
            default: return false
            }
        }

        for url in urls {
            guard let normalizedURL = normalizeURL(url) else {
                continue
            }

            guard shouldAddRepo(normalizedURL) else { continue }
            repoListLock.wait()
            if !handleDistRepo(url) {
                let repo = Repo()
                repo.rawURL = normalizedURL.absoluteString
                repo.suite = "./"
                repo.rawEntry = """
                Types: deb
                URIs: \(repo.repoURL)
                Suites: ./
                Components:
                """
                repo.entryFile = "\(CommandPath.sourcesListD)/sileo.sources"
                repoList.append(repo)
                repos.append(repo)
            }
            repoListLock.signal()
        }
        writeListToFile()
        return repos
    }
    
    private func shouldAddRepo(_ url: URL, _ suite: String="./", _ components: [String]=[]) -> Bool {
        let components = components.filter({$0.isEmpty==false})
        
        guard !hasRepo(with: url, suite: suite, components: components) else { return false }
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if Jailbreak.bootstrap == .procursus {
            guard !(url.host?.localizedCaseInsensitiveContains("apt.bingner.com") ?? false),
                  !(url.host?.localizedCaseInsensitiveContains("test.apt.bingner.com") ?? false),
                  !(url.host?.localizedCaseInsensitiveContains("apt.elucubratus.com") ?? false) else { return false }
        } else {
            guard !(url.host?.localizedCaseInsensitiveContains("apt.procurs.us") ?? false) else { return false }
        }
        return true
        #endif
    }

    public func addDistRepo(url: URL, suites: String, components: String) -> Repo? {
        NSLog("SileoLog: addDistRepo \(url) : \(suites) : \(components)")

        assert((url.host?.count ?? 0) > 0)
        assert(["http","https"].contains(url.scheme?.lowercased()))
        
        var suites = suites.trimmingCharacters(in: .whitespaces)
        if suites.isEmpty { suites = "./" }
        let suitesArray = suites.components(separatedBy: .whitespaces).filter({$0.isEmpty==false})
        guard suitesArray.count <= 1 else {
            return nil
        }
        
        let components = components.trimmingCharacters(in: .whitespaces)
        let componentsArray = components.components(separatedBy: .whitespaces).filter({$0.isEmpty==false})
        guard componentsArray.count <= 1 else {
            return nil
        }
        
        NSLog("SileoLog: \(suites=="./") || \(componentsArray.isEmpty)")
        guard ((suites=="./" ? 1:0) ^ (componentsArray.isEmpty ? 1:0)) == 0 else {
            return nil
        }
        
        guard let normalizedURL = normalizeURL(url) else {
            return nil
        }
        
        guard shouldAddRepo(normalizedURL, suites, componentsArray) else { return nil }

        repoListLock.wait()
        let repo = Repo()
        repo.rawURL = normalizedURL.absoluteString
        repo.suite = suites
        repo.components = componentsArray
        repo.rawEntry = """
        Types: deb
        URIs: \(repo.rawURL)
        Suites: \(suites)
        Components: \(components)
        """
        repo.entryFile = "\(CommandPath.sourcesListD)/sileo.sources"
        repoList.append(repo)
        repoListLock.signal()
        writeListToFile()
        return repo
    }

    @discardableResult func addRepo(with url: URL) -> [Repo] {
        addRepos(with: [url])
    }

    func remove(repos: [Repo]) {
        repoListLock.wait()
        repoList.removeAll { repos.contains($0) }
        repoListLock.signal()
        writeListToFile()
        for repo in repos {
            UserDefaults.standard.removeObject(forKey: "preferredArch_\(repo.url!)")
            UserDefaults.standard.synchronize()
            DatabaseManager.shared.deleteRepo(repo: repo)
            PaymentManager.shared.removeProviders(for: repo)
            DependencyResolverAccelerator.shared.removeRepo(repo: repo)
        }
        DownloadManager.shared.reloadData(recheckPackages: true)
        NotificationCenter.default.post(name: NewsViewController.reloadNotification, object: nil)
    }

    func remove(repo: Repo) {
        remove(repos: [repo])
    }

    func repo(with repo: Repo) -> Repo? {
        let url = URL(string: repo.rawURL)!
        return self.repo(with: url, suite: repo.suite, components: repo.components)
    }
    
    func repo(with url: URL, suite: String="./", components: [String]?=[]) -> Repo? {
        let components = components?.filter({$0.isEmpty==false}) ?? []
        let url = normalizeURL(url)!
        defer { repoListLock.signal() }
        repoListLock.wait()
        
        // apt doesn't like having different url schemes for the same repo
        var urlcomponents = URLComponents(string: url.absoluteString)!
        urlcomponents.scheme = "url"
        
        for repo in repoList {
            var repourlcomponents = URLComponents(string: repo.rawURL)!
            repourlcomponents.scheme = "url"
            
            if urlcomponents == repourlcomponents && repo.suite==suite && Set(repo.components)==Set(components) {
                return repo
            }
        }
        return nil
    }

    func repo(withSourceFile sourceFile: String) -> Repo? {
        repoList.first { $0.rawEntry == sourceFile }
    }

    func hasRepo(with url: URL, suite: String="./", components: [String]?=[]) -> Bool {
        return repo(with: url, suite: suite, components: components) != nil
    }

    private func parseRepoEntry(_ repoEntry: String, at url: URL, withTypes types: [String], uris: [String], suites: [String], components: [String]?) {
        let components = components?.filter({$0.isEmpty==false}) ?? []
        
        guard types.contains("deb") else {
            return
        }

        for repoURL in uris {
            guard let _repoURL = URL(string: repoURL), ["http","https"].contains(_repoURL.scheme?.lowercased()), _repoURL.host != nil else {
                continue
            }
            
            guard !hasRepo(with: _repoURL, suite: suites[0], components: components) else {
                self.hasDuplicateRepo = true
                continue
            }
            
            let repos = suites.map { (suite: String) -> Repo in
                let repo = Repo()
                repo.rawEntry = repoEntry
                repo.rawURL = {
                    repoURL + (repoURL.last == "/" ? "" : "/")
                }()
                var suite = suite
                if suite.isEmpty {
                    suite = "./"
                }
                repo.suite = suite
                repo.components = components
                repo.entryFile = url.absoluteString
                return repo
            }

            repoListLock.wait()
            repoList += repos
            repoListLock.signal()
        }
    }

    var cachePrefix: URL {
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        let listsURL = FileManager.default.documentDirectory.appendingPathComponent("lists")
        if !listsURL.dirExists {
            try? FileManager.default.createDirectory(at: listsURL, withIntermediateDirectories: true)
        }
        return listsURL
        #else
        return URL(fileURLWithPath: CommandPath.lists)
        #endif
    }

    func cachePrefix(for repo: Repo) -> URL {
        var prefix = repo.repoURL
        prefix = String(prefix.drop(prefix: "https://"))
        prefix = String(prefix.drop(prefix: "http://"))
        if !prefix.hasSuffix("/") {
            prefix += "/"
        }
        if repo.isFlat {
            prefix += repo.suite
        }
        prefix = prefix.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "%5f").replacingOccurrences(of: "/", with: "_")
        return cachePrefix.appendingPathComponent(prefix)
    }

    func cacheFile(named name: String, for repo: Repo) -> URL {
        //let arch = DpkgWrapper.architecture.primary.rawValue
        let arch = repo.preferredArch //prevent apt from installing foreign packages
        let prefix = cachePrefix(for: repo)
        if !repo.isFlat && name == "Packages" {
            return prefix
            .deletingLastPathComponent()
                .appendingPathComponent(prefix.lastPathComponent +
                    repo.components.joined(separator: "_") + "_"
                    + "binary-" + arch! + "_"
                    + name)
        }
        return prefix
            .deletingLastPathComponent()
            .appendingPathComponent(prefix.lastPathComponent + name)
    }

    private static let iconQueue = OperationQueue(name: "iconQueue", maxConcurrent: 10)
    private func _checkUpdatesInBackground(_ repos: [Repo]) {
        NSLog("SileoLog: _checkUpdatesInBackground \(repos)")
        defer {
            NSLog("SileoLog: _checkUpdatesInBackground finished")
        }

        let dispatchGroup = DispatchGroup()
        dispatchGroup.notify(queue: .global()) {
            NSLog("SileoLog: _checkUpdatesInBackground background finished")
        }

        for repo in repos {
            
//            NSLog("SileoLog: _checkUpdatesInBackground \(repo.url) \(repo.isLoaded) \(cacheFile(named: "Release", for: repo)) \(cacheFile(named: "Release", for: repo).aptContents)")
            if !repo.isLoaded {
                let releaseFile = cacheFile(named: "Release", for: repo)
                if let info = releaseFile.aptContents,
                    let release = try? ControlFileParser.dictionary(controlFile: info, isReleaseFile: true).0,
                    let repoName = release["origin"] {
                    repo.repoName = repoName
//                    NSLog("SileoLog: _checkUpdatesInBackground \(repo.url) \(repo.repoName)")
                    let links = dataDetector.matches(
                        in: repo.repoName, range: NSRange(repoName.startIndex..<repoName.endIndex, in: repoName)
                    )
//                    NSLog("SileoLog: _checkUpdatesInBackground \(repo.url) \(links)")
                    if !links.isEmpty {
                        repo.repoName = ""
                    }

                    repo.repoDescription = release["description"] ?? ""
                    repo.isLoaded = true
                }
            }

            if !repo.isIconLoaded {

                //prevent hundreds of repos drain/block the Global Dispatch Queue
                //DispatchQueue.global().async {
                dispatchGroup.enter()
                RepoManager.iconQueue.addOperation {
                    defer { dispatchGroup.leave() }
                    @discardableResult func image(for url: URL, scale: CGFloat) -> Bool {
                        let cache = EvanderNetworking.imageCache(url, scale: scale)
                        if let image = cache.1 {
                            DispatchQueue.main.async {
                                repo.repoIcon = image
                            }
                            if !cache.0 {
                                repo.isIconLoaded = true
                                return true
                            }
                        }
                        if let iconData = try? Data(contentsOf: url) {
                            DispatchQueue.main.async {
                                repo.repoIcon = UIImage(data: iconData, scale: scale)
                                EvanderNetworking.saveCache(url, data: iconData)
                            }
                            repo.isIconLoaded = true
                            return true
                        }
                        return false
                    }
                    
                    if repo.url?.host == "apt.thebigboss.org" {
                        let url = StoreURL("deprecatedicons/BigBoss@\(Int(UIScreen.main.scale))x.png")!
                        image(for: url, scale: UIScreen.main.scale)
                    } else {
                        let scale = Int(UIScreen.main.scale)
                        var shouldBreak = false
                        for i in (1...scale).reversed() {
                            guard !shouldBreak else { continue }
                            let filename = i == 1 ? CommandPath.RepoIcon : "\(CommandPath.RepoIcon)@\(i)x"
                            if let iconURL = URL(string: repo.repoURL)?
                                .appendingPathComponent(filename)
                                .appendingPathExtension("png") {
                                shouldBreak = image(for: iconURL, scale: CGFloat(scale))
                            }
                        }
                    }
                    
                }
            }
        }
    }

    func checkUpdatesInBackground() {
        _checkUpdatesInBackground(repoList)
    }
    
    func checkUpdatesInBackground(_ repo: Repo) {
        _checkUpdatesInBackground([repo])
    }

    private func fixLists() {
        #if !targetEnvironment(simulator) && !TARGET_SANDBOX
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: CommandPath.lists, isDirectory: &directory)
        if !exists || !directory.boolValue {
            NSLog("SileoLog: fixLists \(exists) \(directory) \(directory.boolValue)")
            spawnAsRoot(args: [CommandPath.rm, "-rf", rootfs(CommandPath.lists)])
            spawnAsRoot(args: [CommandPath.mkdir, "-p", rootfs(CommandPath.lists)])
            spawnAsRoot(args: [CommandPath.chown, "-R", "root:wheel", rootfs(CommandPath.lists)])
            spawnAsRoot(args: [CommandPath.chmod, "-R", "0755", rootfs(CommandPath.lists)])
        }
        #endif
    }

    @discardableResult
    func queue(
        from url: URL?,
        lastModifiedTime: String? = nil,
        progress: ((EvanderDownloader, DownloadProgress) -> Void)?,
        success: @escaping (EvanderDownloader, Int,  URL) -> Void,
        failure: @escaping (EvanderDownloader?, Int, Error?) -> Void,
        waiting: ((EvanderDownloader, String) -> Void)? = nil
    ) -> EvanderDownloader? {
        NSLog("SileoLog: queue EvanderDownloader \(url)")

        guard let url = url else {
            failure(nil, 520, nil)
            return nil
        }

        var request = URLManager.urlRequest(url)
        if let lastModifiedTime = lastModifiedTime {
            NSLog("SileoLog: If-Modified-Since: \(lastModifiedTime) for \(url)")
            request.setValue(lastModifiedTime, forHTTPHeaderField: "If-Modified-Since")
        }
        guard let task = EvanderDownloader(request: request) else {
            NSLog("SileoLog: EvanderDownloader init failed for \(url)")
            return nil
        }
        task.progressCallback = { task, responseProgress in
            progress?(task, responseProgress)
        }
        task.errorCallback = { task, status, error, url in
            NSLog("SileoLog: errorCallback=\(status) request=\(request) url=\(url) error=\(error)")

            if let url = url {
                try? FileManager.default.removeItem(at: url)
            }
            failure(task, status, error)
        }
        task.didFinishCallback = { task, status, url in
            success(task, status, url)
        }
        task.waitingCallback = { task, message in
            waiting?(task, message)
        }
        task.make()
        return task
    }

    func fetch(
        from url: URL,
        lastModifiedTime: String? = nil,
        withExtensionsUntilSuccess extensions: [String],
        taskupdate: ((EvanderDownloader) -> Void)?,
        progress: ((EvanderDownloader, DownloadProgress) -> Void)?,
        success: @escaping (EvanderDownloader, Int, URL, URL) -> Void,
        failure: @escaping (EvanderDownloader?, Int, Error?) -> Void
    ) {
        guard !extensions.isEmpty else {
            failure(nil, 404, nil)
            return
        }
        let fullURL: URL
        if extensions[0] == "" {
            fullURL = url
        } else {
            fullURL = url.appendingPathExtension(extensions[0])
        }
        let session = queue(
            from: fullURL,
            lastModifiedTime: lastModifiedTime,
            progress: progress,
            success: { task, status, url in
                success(task, status, fullURL, url)
            },
            failure: { task, status, error in
                let newExtensions = Array(extensions.dropFirst())
                guard !newExtensions.isEmpty else { return failure(task, status, error) }
                self.fetch(from: url, lastModifiedTime: lastModifiedTime, withExtensionsUntilSuccess: newExtensions, taskupdate: taskupdate, progress: progress, success: success, failure: failure)
            }
        )
        
        if let session=session {
            taskupdate?(session)
            session.resume()
        } else {
            failure(nil, 520, nil)
        }
    }
    
    private func packagesLastUpdatedTime(_ repo: Repo) -> String? {

        if !repo.packagesExist {
            return nil
        }
        let packagesFile = cacheFile(named: "Packages", for: repo)
        if !packagesFile.exists {
            return nil
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: packagesFile.path),
              let modifiedDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.init(abbreviation: "GMT")
        formatter.dateFormat = "E, d MMM yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US")

        return "\(formatter.string(from: modifiedDate)) GMT"
    }

    public func postProgressNotification(_ repo: Repo?) {
//        DispatchQueue.main.async {
            NotificationCenter.default.post(name: RepoManager.progressNotification, object: repo)
//        }
    }
    
    enum LogType: CustomStringConvertible {
        case error
        case warning

        var description: String {
            switch self {
            case .error:
                return "Error"
            case .warning:
                return "Warning"
            }
        }

        var color: UIColor {
            switch self {
            case .error:
                return UIColor(red: 219/255, green: 44/255, blue: 56/255, alpha: 1)
            case .warning:
                return UIColor(red: 1, green: 231/255, blue: 146/255, alpha: 1)
            }
        }
    }
    
  
    // swiftlint:disable function_body_length
    private func _update (
        force: Bool,
        forceReload: Bool,
        isBackground: Bool,
        repos: [Repo],
        completion: @escaping (Bool, NSAttributedString) -> Void
    ) {
        fixLists()
        
        let loglock = NSLock()
        let errorOutput = NSMutableAttributedString()
        func log(_ message: String, type: LogType) {
            NSLog("SileoLog: \(type)=\(message)")
            loglock.lock()
            errorOutput.append(NSAttributedString(
                string: "\(type): \(message)\n",
                attributes: [.foregroundColor: type.color])
            )
            loglock.unlock()
        }

        
        var reposUpdated = 0
        let dpkgArchitectures = DpkgWrapper.architecture
        let updateGroup = DispatchGroup()

        var backgroundIdentifier: UIBackgroundTaskIdentifier?
        backgroundIdentifier = UIApplication.shared.beginBackgroundTask {
            backgroundIdentifier.map(UIApplication.shared.endBackgroundTask)
            backgroundIdentifier = nil
        }

        var errorsFound = false
        let listlock = NSLock()
        var repos = self.sortedRepoList(repos: repos)
        
        for repo in repos {
            repo.startedRefresh = true
            self.postProgressNotification(repo)
        }

        for iqueue in 0..<min(repos.count, ProcessInfo.processInfo.processorCount * 2 * (isBackground ? 1 : 2)) {
            updateGroup.enter() //enter group before async block
            let repoQueue = DispatchQueue(label: "repo-update-queue-\(iqueue)")
            repoQueue.async {
                while true {
                    listlock.lock()
                    guard !repos.isEmpty else {
                        listlock.unlock()
                        break
                    }
                    let repo = repos.removeFirst()
                    listlock.unlock()

                    let ReleaseFileSemaphore = DispatchSemaphore(value: 0)
                    let PackagesFileSemaphore = DispatchSemaphore(value: 0)
                    let ReleaseGPGFileSemaphore = DispatchSemaphore(value: 0)

                    var preferredArch: String?
                    var optReleaseFile: (url: URL, dict: [String: String])?
                    var optPackagesFile: (url: URL, name: String)?
                    var releaseGPGFileURL: URL?

                    let releaseURL = URL(string: repo.repoURL)!.appendingPathComponent("Release")
                    NSLog("SileoLog: releaseURL=\(releaseURL)")
                    let releaseTask = self.queue(
                        from: releaseURL,
                        progress: { task, progress in
                            repo.releaseProgress = CGFloat(progress.fractionCompleted)
                            self.postProgressNotification(repo)
                        },
                        success: { task, status, fileURL in
                            defer {
                                ReleaseFileSemaphore.signal()
                            }

                            guard let releaseContents = fileURL.aptContents else {
                                log("Could not parse release file from \(releaseURL)", type: .error)
                                errorsFound = true
                                return
                            }

                            let releaseDict: [String: String]
                            do {
                                releaseDict = try ControlFileParser.dictionary(controlFile: releaseContents, isReleaseFile: true).0
                            } catch {
                                log("Could not parse release file: \(error)", type: .error)
                                errorsFound = true
                                return
                            }

                            guard let repoArchs = (releaseDict["architectures"]?.components(separatedBy: " ") ?? releaseDict["architecture"].map { [$0] }) else {
                                log("Didn't find any architectures in \(releaseDict["architectures"]) : \(releaseURL)", type: .error)
                                errorsFound = true
                                return
                            }
                            if repoArchs.contains(dpkgArchitectures.primary.rawValue) {
                                preferredArch = dpkgArchitectures.primary.rawValue
                            } else {
                                for arch in repoArchs {
                                    if dpkgArchitectures.foreign.contains(where: { $0.rawValue == arch } ) {
                                        preferredArch = arch
                                        break
                                    }
                                }
                            }
                            
                            guard preferredArch != nil else {
                                log("Didn't find availabile architectures in \(releaseDict["architectures"]) : \(releaseURL)", type: .error)
                                errorsFound = true
                                return
                            }

                            guard ["components"].allSatisfy(releaseDict.keys.contains) else {
                                try? FileManager.default.removeItem(at: fileURL)
                                log("Could not parse release file.", type: .error)
                                errorsFound = true
                                return
                            }
                            
                            NSLog("SileoLog: optReleaseFile= \(fileURL), \(releaseDict)")
                            optReleaseFile = (fileURL, releaseDict)

                            repo.releaseProgress = 1
                            self.postProgressNotification(repo)
                        },
                        failure: { task, status, error in
                            defer {
                                ReleaseFileSemaphore.signal()
                            }

                            log("\(releaseURL) returned status \(status). \(error?.localizedDescription ?? "")", type: .error)
                            errorsFound = true
//                            repo.releaseProgress = 1
//                            self.postProgressNotification(repo)
                        }
                    )
                    releaseTask?.resume()
                    
                    var startTime = Date()
                    let refreshTimeout: TimeInterval = isBackground ? 10 : 20
                    
                    var releaseGPGTask: EvanderDownloader? = nil
                    defer { releaseGPGTask?.cancel() }
                    let releaseGPGFileDst = self.cacheFile(named: "Release.gpg", for: repo)
                    let releaseGPGURL = URL(string: repo.repoURL)!.appendingPathComponent("Release.gpg")
                    if !self.NO_PGP {
                        releaseGPGTask = self.queue(
                            from: releaseGPGURL,
                            progress: { task, progress in
                                repo.releaseGPGProgress = CGFloat(progress.fractionCompleted)
                                self.postProgressNotification(repo)
                            },
                            success: { task, status, fileURL in
                                defer {
                                    ReleaseGPGFileSemaphore.signal()
                                }
                                releaseGPGFileURL = fileURL
                                repo.releaseGPGProgress = 1
                                self.postProgressNotification(repo)
                            },
                            failure: { task, status, error in
                                defer {
                                    ReleaseGPGFileSemaphore.signal()
                                }

                                if FileManager.default.fileExists(atPath: releaseGPGFileDst.path) {
                                    log("\(releaseGPGURL) returned status \(status). \(error?.localizedDescription ?? "")", type: .error)
                                    errorsFound = true
                                }
    //                            repo.releaseGPGProgress = 1
//                                self.postProgressNotification(repo)
                            }
                        )
                        releaseGPGTask?.resume()
                    } else {
                        repo.releaseGPGProgress = 1
                        self.postProgressNotification(repo)
                    }
                    
                    //stage 2
                    
                    if ReleaseFileSemaphore.wait(timeout: .now() + refreshTimeout - Date().timeIntervalSince(startTime)) != .success {
                        releaseTask?.cancel()
                    }
                    
                    guard let releaseFile = optReleaseFile else {
                        NSLog("SileoLog: optReleaseFile=\(optReleaseFile)")
                        log("Could not find release file for \(repo.repoURL)", type: .error)
                        errorsFound = true
//                        reposUpdated += 1
                        self.checkUpdatesInBackground(repo)
                        continue
                    }
                    
                    //save repo config for dists repo
                    repo.preferredArch = preferredArch
                    
                    var breakOff = false
                    func escapeEarly() {
                        NSLog("SileoLog: breakOff=\(breakOff)")
//                        #if targetEnvironment(macCatalyst)
//                        guard isReleaseGPGValid else { return }
//                        #endif
                        guard !breakOff,
                              !repo.packageDict.isEmpty,
                              repo.packagesExist,
                              optPackagesFile == nil,
                              let releaseFile = optReleaseFile else { NSLog("SileoLog: escapeEarly abort \(breakOff),\(repo.packageDict.isEmpty),\(repo.packagesExist),\(optPackagesFile)"); return }
                        let supportedHashTypes = RepoHashType.allCases.compactMap { type in releaseFile.dict[type.rawValue].map { (type, $0) } }
                        NSLog("SileoLog: supportedHashTypes=\(supportedHashTypes)")
                        guard !supportedHashTypes.isEmpty else { NSLog("SileoLog: empty supported hash"); return }
                        let hashes: (RepoManager.RepoHashType, String)
                        if let tmp = supportedHashTypes.first(where: { $0.0 == RepoHashType.sha512 }) { //Consistent with hashToSave, prefers sha512
                            hashes = tmp
                        } else if let tmp = supportedHashTypes.first(where: { $0.0 == RepoHashType.sha256 }) {
                            hashes = tmp
                        } else { NSLog("SileoLog: no supported hash"); return }
                        NSLog("SileoLog: using \(hashes.0.rawValue) hashtype")
                        let jsonPath = EvanderNetworking._cacheDirectory.appendingPathComponent("RepoHashCache").appendingPathExtension("json")
                        guard let url = URL(string: repo.repoURL),
                              let cachedData = try? Data(contentsOf: jsonPath),
                              let cacheTmp = (try? JSONSerialization.jsonObject(with: cachedData, options: .mutableContainers)) as? [String: [String: String]],
                              let cacheDict = cacheTmp[hashes.0.rawValue] else { NSLog("SileoLog: invalid hash cache"); return }
                        var hashDict = [String: String]()
//                        let extensions = ["zst", "xz", "bz2", "gz", ""] //no lzma???
                        let extensions = ["zst", "xz", "lzma", "bz2", "gz", ""]
                        for ext in extensions {
                            let key = url.appendingPathComponent("Packages").appendingPathExtension(ext).absoluteString
                            NSLog("SileoLog: cacheDict[\(key)] : \(cacheDict[key])")
                            if let hash = cacheDict[key] {
                                hashDict[ext] = hash
                            }
                        }
                        if hashDict.isEmpty { NSLog("SileoLog: hashDict is empty"); return }
                        let repoHashStrings = hashes.1
                        let files = repoHashStrings.components(separatedBy: "\n")
                        for file in files {
                            var seperated = file.components(separatedBy: " ")
                            seperated.removeAll { $0.isEmpty }
                            if seperated.count != 3 { continue }
                            var file = seperated[2]
                            if file.contains("/") {
                                let tmp = file.components(separatedBy: "/")
                                guard let last = tmp.last else { continue }
                                file = last
                            }
                            if file.prefix(8) != "Packages" { continue }
                            var ext = ""
                            if file.contains(".") {
                                let tmp = file.components(separatedBy: ".")
                                guard let last = tmp.last else { continue }
                                ext = last
                            }
                            guard let key = hashDict[ext] else { continue }
                            if key == seperated[0] {
                                breakOff = true
                                repo.packagesProgress = 1
                                self.postProgressNotification(repo)
                                NSLog("SileoLog: breakOff=true, Packages hash not changed")
                                return
                            }
                        }
                    }
                    if !force {
                        //check whether the hash of the Packages file in Release has changed
                        escapeEarly() //may set breakOff=true
                    }

                    if repo.isFlat==false && preferredArch==nil {
                        log("Could not find preferredArch for \(repo.repoURL)", type: .error)
                        errorsFound = true
//                        reposUpdated += 1
                        self.checkUpdatesInBackground(repo)
                        continue
                    }
                    
                    let packagesUrl = repo.packagesURL(arch: preferredArch)
                    var succeededExtension = ""
                    #if !targetEnvironment(simulator) && !TARGET_SANDBOX
                    let extensions = ["zst", "xz", "lzma", "bz2", "gz", ""]
                    #else
                    let extensions = ["xz", "lzma", "bz2", "gz", ""]
                    #endif
                    
                    //request Packages File
                    var packagesTask: EvanderDownloader? = nil;
                    defer { packagesTask?.cancel() }
                    if !breakOff {
                        self.fetch(
                            from: packagesUrl!,
                            lastModifiedTime: force ? nil : self.packagesLastUpdatedTime(repo),
                            withExtensionsUntilSuccess: extensions,
                            taskupdate: { task in
                                packagesTask = task
                            },
                            progress: { task, progress in
                                if !breakOff {
                                    repo.packagesProgress = CGFloat(progress.fractionCompleted)
                                    self.postProgressNotification(repo)
                                } else {
                                    task.cancel()
                                }
                            },
                            success: { task, status, succeededURL, fileURL in
                                defer {
                                    if !breakOff || status == 304 {
                                        PackagesFileSemaphore.signal()
                                    }
                                }
                                
                                if status == 304 {
                                    breakOff = true
                                }
                                
                                if !breakOff {
                                    succeededExtension = succeededURL.pathExtension
                                    
                                    // to calculate the package file name, subtract the base URL from it. Ensure there's no leading /
                                    let repoURL = repo.repoURL
                                    let substringOffset = repoURL.hasSuffix("/") ? 0 : 1
                                    
                                    let fileName = succeededURL.absoluteString.dropFirst(repoURL.count + substringOffset)
                                    optPackagesFile = (fileURL, String(fileName))
                                }

                                repo.packagesProgress = 1
                                self.postProgressNotification(repo)
                            },
                            failure: { task, status, error in
                                defer {
                                    PackagesFileSemaphore.signal()
                                }
                                log("\(packagesUrl) returned status \(status). \(error?.localizedDescription ?? "")", type: .error)
                                errorsFound = true
//                                repo.packagesProgress = 0
//                                self.postProgressNotification(repo)
                            }
                        )
                    }
                    
                    //verify GPG
                    var isReleaseGPGValid = false
                    if !self.NO_PGP {
                        if ReleaseGPGFileSemaphore.wait(timeout: .now() + refreshTimeout - Date().timeIntervalSince(startTime))  != .success {
                            releaseGPGTask?.cancel()
                        }
                        if let releaseGPGFileURL = releaseGPGFileURL {
                            var error: String = ""
                            let validAndTrusted = APTWrapper.verifySignature(key: releaseGPGFileURL.path, data: releaseFile.url.path, error: &error)
                            NSLog("SileoLog: validAndTrusted=\(validAndTrusted) for \(repo.url)")
                            if !validAndTrusted || !error.isEmpty {
                                if FileManager.default.fileExists(atPath: releaseGPGFileDst.path) {
                                    log("Invalid GPG signature at \(releaseGPGURL)", type: .error)
                                    errorsFound = true
                                    #if targetEnvironment(macCatalyst)
                                    repo.packageDict = [:]
//                                    reposUpdated += 1
                                    self.checkUpdatesInBackground(repo)
                                    continue
                                    #endif
                                }
                            } else {
                                isReleaseGPGValid = true
                            }
                        }
                        
                        #if targetEnvironment(macCatalyst)
                        if !isReleaseGPGValid {
                            repo.packageDict = [:]
                            errorsFound = true
                            log("\(repo.repoURL) had no valid GPG signature", type: .error)
//                            reposUpdated += 1
                            self.checkUpdatesInBackground(repo)
                            continue
                        }
                        #endif
                    }
                    
                    //wait for Packages File
                    if !breakOff {
                        if PackagesFileSemaphore.wait(timeout: .now() + refreshTimeout) != .success {
                            packagesTask?.cancel()
                        }
                    }
                    
                    NSLog("SileoLog: optPackagesFile=\(optPackagesFile)  \(repo.url),\(repo.isFlat),\(repo.preferredArch),\(repo.packagesExist),\(breakOff)")
                    let packagesFileDst = self.cacheFile(named: "Packages", for: repo)
                    var skipPackages = false
                    if !breakOff {
                        guard var packagesFile = optPackagesFile else {
                            log("Could not find packages file for \(repo.repoURL)", type: .error)
                            errorsFound = true
//                            reposUpdated += 1
                            self.checkUpdatesInBackground()
                            continue
                        }

                        let supportedHashTypes = RepoHashType.allCases.compactMap { type in releaseFile.dict[type.rawValue].map { (type, $0) } }
                        let releaseFileContainsHashes = !supportedHashTypes.isEmpty
                        var isPackagesFileValid = supportedHashTypes.allSatisfy {
                            self.isHashValid(hashKey: $1, hashType: $0, url: packagesFile.url, fileName: packagesFile.name)
                        }
                        let hashToSave: RepoHashType = supportedHashTypes.contains(where: { $0.0.hashType == .sha512 })
                            ? .sha512 : .sha256
                        if releaseFileContainsHashes && !isPackagesFileValid {
                            log("Hash for \(packagesFile.name) from \(repo.repoURL) is invalid!", type: .error)
                            errorsFound = true
                        }
                        let (shouldSkip, hash) = self.ignorePackages(repo: repo, packagesURL: packagesFile.url, type: succeededExtension, destinationPath: packagesFileDst, hashtype: hashToSave)
                        skipPackages = shouldSkip && !force
                        NSLog("SileoLog: skipPackages=\(skipPackages)")
                        func loadPackageData() {
                            if !skipPackages {
                                do {
                                    #if !targetEnvironment(simulator) && !TARGET_SANDBOX
                                    if succeededExtension == "zst" {
                                        let ret = ZSTD.decompress(path: packagesFile.url)
                                        switch ret {
                                        case .success(let url):
                                            packagesFile.url = url
                                        case .failure(let error):
                                            throw error
                                        }
                                        if let hash = hash {
                                            self.ignorePackage(repo: repo.repoURL, type: succeededExtension, hash: hash, hashtype: hashToSave)
                                        }
                                        return
                                    }

                                    if succeededExtension == "xz" || succeededExtension == "lzma" {
                                        let ret = XZ.decompress(path: packagesFile.url, type: succeededExtension == "xz" ? .xz : .lzma)
                                        switch ret {
                                        case .success(let url):
                                            packagesFile.url = url
                                        case .failure(let error):
                                            throw error
                                        }
                                        if let hash = hash {
                                            self.ignorePackage(repo: repo.repoURL, type: succeededExtension, hash: hash, hashtype: hashToSave)
                                        }
                                        return
                                    }
                                    #endif
                                    if succeededExtension == "bz2" {
                                        let ret = BZIP.decompress(path: packagesFile.url)
                                        switch ret {
                                        case .success(let url):
                                            packagesFile.url = url
                                        case .failure(let error):
                                            throw error
                                        }
                                    } else if succeededExtension == "gz" {
                                        let ret = GZIP.decompress(path: packagesFile.url)
                                        switch ret {
                                        case .success(let url):
                                            packagesFile.url = url
                                        case .failure(let error):
                                            throw error
                                        }
                                    }
                                    if let hash = hash {
                                        self.ignorePackage(repo: repo.repoURL, type: succeededExtension, hash: hash, hashtype: hashToSave)
                                    }
                                } catch {
                                    log("Could not decompress packages from \(repo.repoURL) (\(succeededExtension)): \(error.localizedDescription)", type: .error)
                                    isPackagesFileValid = false
                                    errorsFound = true
                                }
                            }
                        }
                        loadPackageData()

                        if !skipPackages {
                            if !releaseFileContainsHashes || (releaseFileContainsHashes && isPackagesFileValid) {
                                let packageDict = repo.allNewestPackages
                                repo.packageDict = PackageListManager.readPackages(repoContext: repo, packagesFile: packagesFile.url)
                                let databaseChanges = Array(repo.allNewestPackages.values).filter { package -> Bool in
                                    if let tmp = packageDict[package.package] {
                                        if tmp.version == package.version {
                                            return false
                                        }
                                    }
                                    return true
                                }
                                DatabaseManager.shared.addToSaveQueue(packages: databaseChanges)
                                self.update(repo)
                            } else {
                                repo.packageDict = [:]
                                self.update(repo)
                            }
                            reposUpdated += 1
                        }
                        if !releaseFileContainsHashes || (releaseFileContainsHashes && isPackagesFileValid) {
                            if !skipPackages {
                                moveFileAsRoot(from: packagesFile.url, to: packagesFileDst)
                            }
                        } else if releaseFileContainsHashes && !isPackagesFileValid {
                            deleteFileAsRoot(packagesFileDst)
                        }
                        try? FileManager.default.removeItem(at: packagesFile.url)
                    }
                    if (skipPackages || breakOff) && FileManager.default.fileExists(atPath: packagesFileDst.path) {
                        let attributes = [FileAttributeKey.modificationDate: Date()]
                        try? FileManager.default.setAttributes(attributes, ofItemAtPath: packagesFileDst.path)
                    }

                    if !self.NO_PGP {
                        if FileManager.default.fileExists(atPath: releaseGPGFileDst.path) && !isReleaseGPGValid {
//                            reposUpdated += 1
                            self.checkUpdatesInBackground(repo)
                            continue
                        }
                        if let releaseGPGFileURL = releaseGPGFileURL {
                            if isReleaseGPGValid {
                                moveFileAsRoot(from: releaseGPGFileURL, to: releaseGPGFileDst)
                            } else {
                                deleteFileAsRoot(releaseGPGFileDst)
                            }
                        }
                        releaseGPGFileURL.map { try? FileManager.default.removeItem(at: $0) }
                    } else {
                        if FileManager.default.fileExists(atPath: releaseGPGFileDst.path) {
                            deleteFileAsRoot(releaseGPGFileDst)
                        }
                    }
                    
                    let releaseFileDst = self.cacheFile(named: "Release", for: repo)
                    moveFileAsRoot(from: releaseFile.url, to: releaseFileDst)
                    try? FileManager.default.removeItem(at: releaseFile.url)
                    
                    self.checkUpdatesInBackground(repo)
                    
                    if preferredArch != dpkgArchitectures.primary.rawValue {
                        let packages = PackageListManager.shared.packageList(identifier: "--contextRootHide", repoContext: repo)
                        if packages.count > 0 {
                            log("Didn't find availabile architectures in \(repo.releaseDict?["architectures"]) : \(releaseURL)", type: .warning)
                            errorsFound = true
                        }
                    }
                    
                    //dismiss progress bar
                    repo.releaseProgress = 0
                    repo.packagesProgress = 0
                    repo.releaseGPGProgress = 0
                    repo.startedRefresh = false
                    self.postProgressNotification(repo)
                    
                } //while true
                updateGroup.leave()
            }
        }

        updateGroup.notify(queue: .main) {
            #if !targetEnvironment(macCatalyst)
            var files = self.cachePrefix.implicitContents
            
//            EvanderDownloader.dump()

            var expectedFiles: [String] = []
            expectedFiles = self.repoList.flatMap { (repo: Repo) -> [String] in
                var names = [
                    "Release",
                    "Release.gpg"
                ]
                if repo.packagesExist {
                    names.append("Packages")
                }
                #if ENABLECACHINGBETA
                names.append("Packages.plist")
                #endif
                
                //dismiss progress bar for any repo (also broken repos)
                repo.releaseProgress = 0
                repo.packagesProgress = 0
                repo.releaseGPGProgress = 0
                repo.startedRefresh = false
                
                return names.map {
                    self.cacheFile(named: $0, for: repo).lastPathComponent
                }
            }
            expectedFiles.append("lock")
            expectedFiles.append("partial")

            files.removeAll { expectedFiles.contains($0.lastPathComponent) }
            files.forEach(deleteFileAsRoot)
            #endif
            
            //dismiss progress bar for broken repos
            self.postProgressNotification(nil)
            
            NSLog("SileoLog: reposUpdated=\(reposUpdated)")
            if reposUpdated > 0 {
                DownloadManager.aptQueue.async {
                    DatabaseManager.shared.saveQueue()
                    DownloadManager.shared.repoRefresh()
                    DispatchQueue.global().async {
                        DependencyResolverAccelerator.shared.preflightInstalled()
                        CanisterResolver.shared.queueCache()
                    }
                }
            }
            
            DispatchQueue.main.async {
                if reposUpdated > 0 {
                    NotificationCenter.default.post(name: PackageListManager.reloadNotification, object: nil)
                    NotificationCenter.default.post(name: NewsViewController.reloadNotification, object: nil)
                }
                completion(errorsFound, errorOutput)
                
                // This method can be safely called on a non-main thread.
                backgroundIdentifier.map(UIApplication.shared.endBackgroundTask)
            }
        }
    }

    private func ignorePackage(repo: String, type: String, hash: String, hashtype: RepoHashType) {
        guard let repo = URL(string: repo) else { return }
        let repoPath = repo.appendingPathComponent("Packages").appendingPathExtension(type)
        let jsonPath = EvanderNetworking._cacheDirectory.appendingPathComponent("RepoHashCache").appendingPathExtension("json")
        var dict = [String: [String: String]]()
        if let cachedData = try? Data(contentsOf: jsonPath),
           let tmp = try? JSONSerialization.jsonObject(with: cachedData, options: .mutableContainers) as? [String: [String: String]] {
            dict = tmp
        }
        var hashDict = dict[hashtype.rawValue] ?? [:]
        hashDict[repoPath.absoluteString] = hash
        dict[hashtype.rawValue] = hashDict
        if let jsonData = try? JSONEncoder().encode(dict) {
            try? jsonData.write(to: jsonPath)
        }
    }

    private func ignorePackages(repo: Repo, packagesURL: URL, type: String, destinationPath: URL, hashtype: RepoHashType) -> (Bool, String?) {
        guard !repo.packageDict.isEmpty,
              repo.packagesExist,
              let repo = URL(string: repo.repoURL),
              let hash = packagesURL.hash(ofType: hashtype.hashType) else { return (false, nil) }
        if !FileManager.default.fileExists(atPath: destinationPath.path) {
            return (false, hash)
        }
        let repoPath = repo.appendingPathComponent("Packages").appendingPathExtension(type)
        let jsonPath = EvanderNetworking._cacheDirectory.appendingPathComponent("RepoHashCache").appendingPathExtension("json")
        let cachedData = try? Data(contentsOf: jsonPath)
        let dict = (try? JSONSerialization.jsonObject(with: cachedData ?? Data(), options: .mutableContainers) as? [String: [String: String]]) ?? [String: [String: String]]()
        let hashDict = dict[hashtype.rawValue] ?? [:]
        return ((hashDict[repoPath.absoluteString]) == hash, hash)
    }

    func update(force: Bool, forceReload: Bool, isBackground: Bool, repos: [Repo] = RepoManager.shared.repoList, completion: @escaping (Bool, NSAttributedString) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            PackageListManager.shared.initWait()
//            DispatchQueue.main.async {
                self._update(force: force, forceReload: forceReload, isBackground: isBackground, repos: repos, completion: completion)
//            }
        }
    }

    func isHashValid(hashKey: String, hashType: RepoHashType, url: URL, fileName: String) -> Bool {
        guard let refhash = url.hash(ofType: hashType.hashType) else { return false }

        let hashEntries = hashKey.components(separatedBy: "\n")

        return hashEntries.contains {
            var components = $0.components(separatedBy: " ")
            components.removeAll { $0.isEmpty }

            return components.count >= 3 &&
                   components[0] == refhash &&
                   components[2] == fileName
        }
    }
    
    public func parseListFile(at url: URL, isImporting: Bool = false) {
        // if we're importing, then it doesn't matter if the file is a cydia.list
        // otherwise, don't parse the file
        if Jailbreak.bootstrap == .procursus, !isImporting {
            guard url.lastPathComponent != "cydia.list" else {
                return
            }
        }
        guard let rawList = try? String(contentsOf: url) else { return }

        let repoEntries = rawList.components(separatedBy: .newlines)
        for repoEntry in repoEntries {
            let parts = repoEntry.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter({$0.isEmpty==false})
            guard parts.count >= 3 else {
                continue
            }

            let type = parts[0]
            let uri = parts[1]
            let suite = parts[2]
            let components = (parts.count > 3) ? Array(parts[3...]) : nil

            parseRepoEntry(repoEntry, at: url, withTypes: [type], uris: [uri], suites: [suite], components: components)
        }
    }

    public func parsePlainTextFile(at url: URL) {
        guard let rawSources = try? String(contentsOf: url) else {
            return
        }
        
        for source in rawSources.components(separatedBy: .newlines) {
            let parts = source.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter({$0.isEmpty==false})
            
            let uri = parts[0]
            
            guard let _ = URL(string: uri) else { continue }
            
            let suite = (parts.count > 1) ? parts[1] : "./"
            let components = (parts.count > 2) ? Array(parts[2...]) : nil
            
            parseRepoEntry(rawSources, at: url, withTypes: ["deb"], uris: [uri], suites: [suite], components: components)
        }
    }
    
    public func parseSourcesFile(at url: URL) {
        guard let rawSources = try? String(contentsOf: url) else {
            NSLog("SileoLog: [Sileo] \(#function): couldn't get rawSources. we are out of here!")
            return
        }
        let repoEntries = rawSources.components(separatedBy: "\n\n")
        for repoEntry in repoEntries where !repoEntry.isEmpty {
            guard let repoData = try? ControlFileParser.dictionary(controlFile: repoEntry, isReleaseFile: false).0,
                  let rawTypes = repoData["types"],
                  let rawUris = repoData["uris"],
                  let rawSuites = repoData["suites"],
                  let rawComponents = repoData["components"]
            else {
                print("\(#function): Couldn't parse repo data for Entry \(repoEntry)")
                continue
            }

            let types = rawTypes.components(separatedBy: " ")
            let uris = rawUris.components(separatedBy: " ")
            let suites = rawSuites.components(separatedBy: " ")

            let allComponents = rawComponents.components(separatedBy: " ")
            let components: [String]?
            if allComponents.count == 1 && allComponents[0] == "" {
                components = nil
            } else {
                components = allComponents
            }

            parseRepoEntry(repoEntry, at: url, withTypes: types, uris: uris, suites: suites, components: components)
        }
    }

    func writeListToFile() {
        repoListLock.wait()
        
        if Jailbreak.bootstrap != .elucubratus || Jailbreak.bootstrap != .unc0ver {
            var rawRepoList = ""
            var added: Set<String> = []
            for repo in repoList {
                guard URL(fileURLWithPath: repo.entryFile).lastPathComponent == "sileo.sources",
                      !added.contains(repo.rawEntry)
                else {
                    continue
                }
                rawRepoList += "\(repo.rawEntry)\n\n"
                added.insert(repo.rawEntry)
            }

            #if targetEnvironment(simulator) || TARGET_SANDBOX
            do {
                try rawRepoList.write(to: sourcesURL, atomically: true, encoding: .utf8)
            } catch {
                print("Couldn't save with \(error)")
            }
            
            #else

            let sileoList = "\(CommandPath.prefix)/etc/apt/sources.list.d/sileo.sources"
            let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try rawRepoList.write(to: tempPath, atomically: true, encoding: .utf8)
            } catch {
                return
            }
            
            #if targetEnvironment(macCatalyst)
            spawnAsRoot(args: [CommandPath.cp, "-f", rootfs("\(tempPath.path)"), rootfs("\(sileoList)")])
            #else
            spawnAsRoot(args: [CommandPath.cp, "--reflink=never", "-f", rootfs("\(tempPath.path)"), rootfs("\(sileoList)")])
            #endif
            spawnAsRoot(args: [CommandPath.chmod, "0644", rootfs("\(sileoList)")])

            #endif
        } else {
            // > but if you wanted to, just edit the cydia file too and update cydia's prefs
            let defaults = UserDefaults(suiteName: "com.saurik.Cydia")
            var sourcesDict = [String: Any]()
            var rawRepoList = ""
            var added: Set<String> = []
            
            for repo in repoList {
                let rawEntry = "deb \(repo.rawURL) \(repo.suite) \(repo.components.first ?? "")"
                if added.contains(rawEntry) { continue }
                rawRepoList += "\(rawEntry)\n"
                added.insert(rawRepoList)
                let dict: [String: Any] = [
                    "Distribution": repo.suite,
                    "Type": "deb",
                    "Sections": repo.components,
                    "URI": repo.rawURL
                ]
                sourcesDict["deb:\(repo.rawURL):\(repo.suite)"] = dict
            }
            defaults?.setValue(sourcesDict, forKey: "CydiaSources")
            defaults?.synchronize()
            
            let cydiaList = URL(fileURLWithPath: "/var/mobile/Library/Caches/com.saurik.Cydia/sources.list")
            try? rawRepoList.write(to: cydiaList, atomically: true, encoding: .utf8)
        }
        
        repoListLock.signal()
    }
    
    public func getUniqueName(repo: Repo) -> String {
        defer { repoListLock.signal() }
        repoListLock.wait()
        
        var uniqueUrl: String = repo.displayURL
        
        for repo2 in self.repoList {
            if repo.displayURL == repo2.displayURL && repo != repo2 {
                uniqueUrl = repo.url?.absoluteString ?? "?"
                break
            }
        }
        
        for repo2 in self.repoList {
            if repo.url == repo2.url && repo != repo2 {
                uniqueUrl = repo.primaryComponentURL?.absoluteString ?? "?"
                break
            }
        }
        
        if repo.repoName.isEmpty {
            return uniqueUrl
        }
        
        for repo2 in self.repoList {
            if repo.repoName == repo2.repoName && repo != repo2  {
                return uniqueUrl
            }
        }

        return repo.repoName
    }
}

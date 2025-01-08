//
//  SourcesViewController.swift
//  Sileo
//
//  Created by CoolStar on 9/22/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

final class SourcesViewController: SileoViewController {
    private var sortedRepoList: [Repo] = []
    var updatingRepoList: [Repo] = []
    
    var presentRepoUrl: URL?
    var defaultPagePresent = false
    var detailedPageUserPresent = false
    
    private var tableView = SileoTableView(frame: .zero, style: .plain)
    public var refreshControl = UIRefreshControl()
    private var inRefreshing = false
    
    static let refreshReposNotification = Notification.Name("SourcesViewController.refreshReposNotification")
    static let reloadDataNotification = Notification.Name("SourcesViewController.reloadDataNotification")
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        RepoManager.shared.checkUpdatesInBackground()
        
        weak var weakSelf: SourcesViewController? = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(self.reloadRepo(_:)),
                                               name: RepoManager.progressNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(forName: SourcesViewController.refreshReposNotification, object: nil, queue: .main) { _ in
            self.refreshSources(forceUpdate: false, forceReload: false, isBackground: true, useRefreshControl: false, useErrorScreen: false, completion: nil)
        }
        
        NotificationCenter.default.addObserver(forName: SourcesViewController.reloadDataNotification, object: nil, queue: .main) { _ in
            self.reloadData()
        }
    }
    
    func canEditRow(indexPath: IndexPath) -> Bool {
        if indexPath.section == 0 {
            return false
        }
        
        let repo = sortedRepoList[indexPath.row]
        if Jailbreak.bootstrap == .procursus {
            return repo.entryFile.hasSuffix("/sileo.sources")
        }
        return repo.url?.host != "apt.bingner.com"
    }
    
    func controller(indexPath: IndexPath) -> CategoryViewController {
        let categoryVC = CategoryViewController(style: .plain)
        categoryVC.title = String(localizationKey: "All_Packages.Title")
        
        if indexPath.section == 1 {
            let repo = sortedRepoList[indexPath.row]
            categoryVC.repoContext = repo
            categoryVC.title = repo.repoName
        }
        
        let touchGestureRecognizer = TouchGestureRecognizer(target: self, action: #selector(detailedPageUserInteracted))
        categoryVC.view.addGestureRecognizer(touchGestureRecognizer)
        
        return categoryVC
    }

    @objc func detailedPageUserInteracted() {
        self.detailedPageUserPresent = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        #if !targetEnvironment(macCatalyst)
        tableView.refreshControl = refreshControl
        #endif
        refreshControl.addTarget(self, action: #selector(refreshSources(_:)), for: .valueChanged)
        
        self.title = String(localizationKey: "Sources_Page")
        tableView.register(SourcesTableViewFooter.self, forHeaderFooterViewReuseIdentifier: "Sileo.SourcesTableViewFooter")
        
        updateSileoColors()
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(self.updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        
        tableView.delegate = self
        tableView.dataSource = self
        self.tableView.separatorInset = UIEdgeInsets(top: 72, left: 0, bottom: 0, right: 0)
        self.tableView.separatorColor = UIColor(white: 0, alpha: 0.2)
        self.setEditing(false, animated: false)
        
        self.navigationController?.navigationBar.superview?.tag = WHITE_BLUR_TAG
        #if targetEnvironment(macCatalyst)
        let nav = self.navigationItem
        nav.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSource(_:)))
        nav.leftBarButtonItem = UIBarButtonItem(title: "Refresh", style: .done, target: self, action: #selector(refreshSources(_:)))
        #endif
    
        NotificationCenter.default.addObserver(weakSelf as Any, selector: #selector(handleImageUpdate(_:)), name: SourcesTableViewCell.repoImageUpdate, object: nil)
        
// self.splitViewController?.isCollapsed may not be ready yet
//        presentDefaultPage()
        
        self.splitViewController?.delegate = self
    }

    private func presentDefaultPage() {
        NSLog("SileoLog: presentDefaultPage \(self.splitViewController) \(self.splitViewController?.isCollapsed)")
        if self.splitViewController?.isCollapsed == false {
            let indexPath = IndexPath(row: 0, section: 0)
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            if !defaultPagePresent || presentRepoUrl != nil {
                presentRepoUrl = nil
                defaultPagePresent = true
                detailedPageUserPresent = false
                self.tableViewSelectRowAt(tableView: tableView, indexPath: indexPath)
            }
        }
    }
    
    private func deselectRepos() {
        if self.splitViewController?.isCollapsed ?? false {
            self.detailedPageUserPresent = false
            if let selectedRows = tableView.indexPathsForSelectedRows {
                 for indexPath in selectedRows {
                     tableView.deselectRow(at: indexPath, animated: false)
                 }
             }
        }
    }
    
    override func viewWillLayoutSubviews() {
        NSLog("SileoLog: SourcesViewController.viewWillLayoutSubviews")
        super.viewDidLayoutSubviews()

    }

    override func viewDidLayoutSubviews() {
        NSLog("SileoLog: SourcesViewController.viewDidLayoutSubviews \(self.splitViewController?.isCollapsed) \(self.presentRepoUrl)")
        super.viewDidLayoutSubviews()

        if self.splitViewController?.isCollapsed == false
        {
            if self.presentRepoUrl == nil
            {
                self.presentDefaultPage()
                return
            }

            let sourceSection = 1
            for i in 0..<tableView.numberOfRows(inSection: sourceSection) {
                let repo = sortedRepoList[i]
                if repo.url == self.presentRepoUrl {
                    let indexPath = IndexPath(row: i, section: sourceSection)
                    tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                }
            }
        }
        else
        {
            deselectRepos()
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        NSLog("SileoLog: SourcesViewController.traitCollectionDidChange")
        updateSileoColors()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        NSLog("SileoLog: SourcesViewController.viewWillTransition \(self.splitViewController?.isCollapsed) \(self.presentRepoUrl)")
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(refreshSources(_:)), discoverabilityTitle: "Refresh Sources"),
            UIKeyCommand(input: "+", modifierFlags: .command, action: #selector(addSource(_:)), discoverabilityTitle: "Add Source")
        ]
    }
    
    @objc func updateSileoColors() {
        self.tableView.backgroundColor = .sileoBackgroundColor
        self.tableView.separatorColor = .sileoSeparatorColor
        self.statusBarStyle = .default
        view.backgroundColor = .sileoBackgroundColor
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NSLog("SileoLog: SourcesViewController.viewWillAppear")
        super.viewWillAppear(animated)
        updateSileoColors()
        
        if inRefreshing {
            if let refreshControl = tableView.refreshControl {
                refreshControl.endRefreshing()
                DispatchQueue.main.async { //reactive animate
                    refreshControl.beginRefreshing()
                }
            }
        }
        
        deselectRepos()
    }

    override func viewDidAppear(_ animated: Bool) {
        NSLog("SileoLog: SourcesViewController.viewDidAppear \(self.splitViewController?.isCollapsed) \(self.tableView.indexPathsForSelectedRows)")
        super.viewDidAppear(animated)
        self.navigationController?.navigationBar._hidesShadow = true
        self.tableView.backgroundColor = .sileoBackgroundColor
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if inRefreshing {
            if let refreshControl = tableView.refreshControl {
                refreshControl.endRefreshing()
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.navigationController?.navigationBar._hidesShadow = false
    }
    
    @objc func toggleEditing(_ sender: Any?) {
        self.setEditing(!self.isEditing, animated: true)
    }
    
    #if !targetEnvironment(macCatalyst)
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        self.tableView.setEditing(editing, animated: animated)
        
        FRUIView.animate(withDuration: animated ? 0.2 : 0.0) {
            let nav = self.navigationItem
            
            if editing {
                let exportTitle = String(localizationKey: "Export")
                nav.leftBarButtonItem = UIBarButtonItem(title: String(localizationKey: "Done"), style: .done, target: self, action: #selector(self.toggleEditing(_:)))
                nav.rightBarButtonItem = UIBarButtonItem(title: exportTitle, style: .plain, target: self, action: #selector(self.exportSources(_:)))
            } else {
                nav.leftBarButtonItem = UIBarButtonItem(title: String(localizationKey: "Edit"), style: .done, target: self, action: #selector(self.toggleEditing(_:)))
                if #available(iOS 14.0, *) {
                    let promptAddRepoAction = UIAction(title: "Add Repo", image: .init(systemName: "plus.circle")) { _ in
                        self.addSource(nil)
                    }
                    
                    let importReposAction = UIAction(title: "Import Repos", image: .init(systemName: "archivebox")) { _ in
                        self.promptImportRepos()
                    }
                    
                    let menu = UIMenu(title: "Add Repos", children: [promptAddRepoAction, importReposAction])
                    nav.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: promptAddRepoAction, menu: menu)
                } else {
                    nav.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addSource(_:)))
                }
            }
            
        }
    }
    #endif
    
    func importRepos(fromURL url: URL) {
        let _tmpManager = RepoManager()
        
        if url.pathExtension == "list" {
            _tmpManager.parseListFile(at: url, isImporting: true)
        } else if url.pathExtension == "sources" {
            _tmpManager.parseSourcesFile(at: url)
        } else {
            _tmpManager.parsePlainTextFile(at: url)
        }
        
        var newRepos:[Repo] = []
        for repo in _tmpManager.repoList {
            if let url = URL(string: repo.rawURL) {
                if let newRepo = RepoManager.shared.addDistRepo(url: url, suites: repo.suite, components: repo.components.joined(separator: " ")) {
                    newRepos.append(newRepo)
                }
            }
        }

        if newRepos.count > 0 {
            self.reloadData()
            self.updateSpecific(newRepos)
        }
    }
    
    @available(iOS 14.0, *)
    private func promptImportRepos() {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        let delegate = SourcesPickerImporterDelegate.shared
        delegate.sourcesVC = self
        controller.delegate = delegate
        self.present(controller, animated: true, completion: nil)
    }
    
    class SourcesPickerImporterDelegate: NSObject, UIDocumentPickerDelegate {
        var sourcesVC: SourcesViewController? = nil
        
        static var shared = SourcesPickerImporterDelegate()
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let firstURL = urls.first else {
                return
            }
            
            sourcesVC?.importRepos(fromURL: firstURL)
        }
    }
     
    @objc private func handleImageUpdate(_ notification: Notification) {
        NSLog("SileoLog: handleImageUpdate \(notification.object)")
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.handleImageUpdate(notification)
            }
            return
        }
        guard let url = notification.object as? String else { return }
        for cell in tableView.loadedCells {
            guard let cell = cell as? SourcesTableViewCell, let repo = cell.repo else { continue }
            if repo.rawURL == url {
                NSLog("SileoLog: cell.image=\(repo.repoIcon)")
                cell.image(repo)
                return
            }
        }
    }
    
    @objc func refreshSources(_ sender: UIRefreshControl?) {
        self.refreshSources(forceUpdate: false, forceReload: true)
    }
    
    func refreshSources(forceUpdate: Bool, forceReload: Bool) {
        self.refreshSources(forceUpdate: forceUpdate, forceReload: forceReload, isBackground: false, useRefreshControl: false, useErrorScreen: true, completion: nil)
    }
    
    private func addToQueue(_ repo: Repo) {
        if !updatingRepoList.contains(where: { $0.rawURL == repo.rawURL }) {
            updatingRepoList.append(repo)
        }
    }
    
    private func removeFromQueue(_ repo: Repo) {
        if let index = updatingRepoList.firstIndex(where: { $0.rawURL == repo.rawURL }) {
            updatingRepoList.remove(at: index)
        }
    }
    
    private func killIndicator() {
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        let badge = item?.view()?.value(forKey: "_badge") as? UIView ?? UIView()
        self.refreshControl.endRefreshing()
        self.inRefreshing = false
        let indicators = badge.subviews.filter { $0 is UIActivityIndicatorView }
        for indicator in indicators {
            if let indicator = indicator as? UIActivityIndicatorView {
                indicator.removeFromSuperview()
                indicator.stopAnimating()
            }
        }
        item?.badgeValue = nil
    }
    
    func refreshSources(forceUpdate: Bool, forceReload: Bool, isBackground: Bool, useRefreshControl: Bool, useErrorScreen: Bool, completion: ((Bool, NSAttributedString) -> Void)?) {
        NSLog("SileoLog: refreshSources \(forceUpdate) \(forceReload) \(isBackground) \(useRefreshControl) \(useErrorScreen)")
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
            fatalError("OK iOS...")
        }
        let indicatorView = UIActivityIndicatorView(style: style)
        let badge = item?.view()?.value(forKey: "_badge") as? UIView
        
        if updatingRepoList.isEmpty {
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
            
            self.inRefreshing = true
            if let refreshControl = tableView.refreshControl, !refreshControl.isRefreshing {
                refreshControl.beginRefreshing()
            }
        }
        
        for repo in sortedRepoList {
            addToQueue(repo)
        }
        RepoManager.shared.update(force: forceUpdate, forceReload: forceReload, isBackground: isBackground, completion: { didFindErrors, errorOutput in
            NSLog("SileoLog: useErrorScreen=\(useErrorScreen) didFindErrors=\(didFindErrors):\(errorOutput)")
            for repo in self.sortedRepoList {
                self.removeFromQueue(repo)
            }
            self.killIndicator()
            
            if didFindErrors, useErrorScreen {
                self.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
            
            if let completion = completion {
                completion(didFindErrors, errorOutput)
            }
        })
    }
    
    func updateSingleRepo(_ repo: Repo) {

        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        
        if updatingRepoList.isEmpty {
            let badge = item?.view()?.value(forKey: "_badge") as? UIView
            guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
                fatalError("OK iOS...")
            }
            let indicatorView = UIActivityIndicatorView(style: style)
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
        }
        
        RepoManager.shared.update(force: true, forceReload: true, isBackground: false, repos: [repo], completion: { didFindErrors, errorOutput in
            self.removeFromQueue(repo)
            if self.updatingRepoList.isEmpty {
                self.killIndicator()
            }

            if didFindErrors {
                self.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
        })
    }
    
    func updateSpecific(_ repos: [Repo]) {
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""

        if updatingRepoList.isEmpty {
            let badge = item?.view()?.value(forKey: "_badge") as? UIView
            guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
                fatalError("OK iOS...")
            }
            let indicatorView = UIActivityIndicatorView(style: style)
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
        }
        
        for repo in repos {
            addToQueue(repo)
        }
        
        RepoManager.shared.update(force: true, forceReload: true, isBackground: false, repos: repos) { [weak self] didFindErrors, errorOutput in
            guard let strongSelf = self else { return }
            for repo in repos {
                strongSelf.removeFromQueue(repo)
            }
            if strongSelf.updatingRepoList.isEmpty {
                strongSelf.killIndicator()
            }
            if didFindErrors {
                strongSelf.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
        }
    }
    
    func showRefreshErrorViewController(errorOutput: NSAttributedString, completion: (() -> Void)?) {
        let errorVC = SourcesErrorsViewController(nibName: "SourcesErrorsViewController", bundle: nil)
        errorVC.attributedString = errorOutput
        let navController = UINavigationController(rootViewController: errorVC)
        navController.navigationBar.barStyle = .blackTranslucent
        navController.modalPresentationStyle = .formSheet
        self.present(navController, animated: true, completion: completion)
    }
    
    func reSortList() {
        sortedRepoList = RepoManager.shared.sortedRepoList()
    }
    
    private func deleteRepo(at indexPath: IndexPath) {
        if DownloadManager.shared.queueRunning {
            TabBarController.singleton?.presentPopupController()
            return
        }
        
        let repo = self.sortedRepoList[indexPath.row]
        RepoManager.shared.remove(repo: repo)
        tableView.deleteRows(at: [indexPath], with: .fade)
        self.reSortList()
        updatingRepoList.removeAll { $0 == repo }
        self.updateFooterCount()
        NotificationCenter.default.post(name: PackageListManager.reloadNotification, object: nil)
        
        if repo.url == self.presentRepoUrl {
            presentDefaultPage()
        }
    }
    
    @objc func reloadRepo(_ notification: NSNotification) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.reloadRepo(notification)
            }
            return
        }
        if let repo = notification.object as? Repo {
            guard let idx = sortedRepoList.firstIndex(of: repo),
            let cell = self.tableView.cellForRow(at: IndexPath(row: idx, section: 1)) as? SourcesTableViewCell else {
                return
            }
            let cellRepo = cell.repo
            cell.repo = cellRepo
            cell.layoutSubviews()
        } else if let count = notification.object as? Int {
            DispatchQueue.main.async {
                guard let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? SourcesTableViewCell else { return }
                cell.installedLabel.text = "\(count)"
            }
        } else {
            for cell in tableView.loadedCells {
                if let sourcesCell = cell as? SourcesTableViewCell {
                    let cellRepo = sourcesCell.repo
                    sourcesCell.repo = cellRepo
                    sourcesCell.layoutSubviews()
                }
            }
        }
    }
    
    func reloadData() {
        self.reSortList()
        self.tableView.reloadData()
    }
    
    @objc func exportSources(_ sender: Any?) {
        let titleString = String(localizationKey: "Export")
        let msgString = String(localizationKey: "Export_Sources")
        let alert = UIAlertController(title: titleString, message: msgString, preferredStyle: .alert)
        
        let yesString = String(localizationKey: "Export_Yes")
        let yesAction = UIAlertAction(title: yesString, style: .default, handler: { _ in
            let repos = self.sortedRepoList.filter({$0.aptSource != nil}).map({ $0.aptSource! }).joined(separator: "\n")
            let activityVC = UIActivityViewController(activityItems: [repos], applicationActivities: nil)
            
            activityVC.popoverPresentationController?.sourceView = self.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            
            self.present(activityVC, animated: true, completion: nil)
        })
        
        alert.addAction(yesAction)
        
        let noString = String(localizationKey: "Export_No")
        let noAction = UIAlertAction(title: noString, style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(noAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    public func presentAddSourceEntryField(url: URL?) {
        let title = String(localizationKey: "Add_Source.Title")
        let msg = String(localizationKey: "Add_Source.Body")
        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "URL"
            if let urlString = url?.absoluteString {
                let parsedURL = urlString.replacingOccurrences(of: "sileo://source/", with: "")
                textField.text = parsedURL
            } else {
                textField.text = "https://"
            }
            textField.keyboardType = .URL
            textField.addTarget(self, action: #selector(Self.textFieldDidChange(_:)), for: .editingChanged)
        }
        
        let addAction = UIAlertAction(title: String(localizationKey: "Add_Source.Button.Add"), style: .default, handler: { [weak alert] _ in
            self.dismiss(animated: true, completion: nil)
            if let repoURL = alert?.textFields?[0].text, let url = URL(string: repoURL) {
                if ["http","https"].contains(url.scheme?.lowercased()) && url.host != nil {
                    self.handleSourceAdd(sources: [url.absoluteString], bypassFlagCheck: false)
                }
            }
        })
        alert.addAction(addAction)
        
        let distRepoAction = UIAlertAction(title: String(localizationKey: "Add_Dist_Repo"), style: .default, handler: { [weak alert]  _ in
            self.dismiss(animated: true, completion: nil)
            self.addDistRepo(string: alert?.textFields?[0].text)
        })
        alert.addAction(distRepoAction)
        
        let cancelAcction = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(cancelAcction)
        
        present(alert, animated: true, completion: nil)
    }
    
    func presentAddClipBoardPrompt(sources: [String]) {
        if sources.isEmpty {
            // I'm not quite sure how this happens, but it does sooooo
            return self.presentAddSourceEntryField(url: nil)
        }
        let count = sources.count

        let titleText = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Title"), count, count)
        let addText = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Button.Add"), count, count)
        let manualText = String(localizationKey: "Auto_Add_Pasteboard_Sources.Button.Manual")
        
        var msg = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Body_Intro"), sources.count)
        msg.append(contentsOf: "\n\n")
        msg.append(sources.compactMap { source -> String in
            "\"\(source)\""
        }.joined(separator: "\n"))
        
        let alert = UIAlertController(title: titleText, message: msg, preferredStyle: .alert)
        
        let addAction = UIAlertAction(title: addText, style: .default, handler: { _ in
            self.handleSourceAdd(sources: sources, bypassFlagCheck: false)
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(addAction)
        
        let manualAction = UIAlertAction(title: manualText, style: .default, handler: { _ in
            self.presentAddSourceEntryField(url: nil)
        })
        alert.addAction(manualAction)
        
        let cancelAction = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func addDistRepo(string: String?, suites: String?=nil, components: String?=nil) {
        let title = String(localizationKey: "Add_Source.Title")
        let msg = String(localizationKey: "Add_Dist_Repo")
        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "URL"
            textField.text = string
            textField.keyboardType = .URL
            textField.addTarget(self, action: #selector(Self.textFieldDidChange(_:)), for: .editingChanged)
        }
        alert.addTextField { textField in
            textField.placeholder = "Suites"
            textField.text = suites
            textField.keyboardType = .URL
        }
        alert.addTextField { textField in
            textField.placeholder = "Components"
            textField.text = components
            textField.keyboardType = .URL
        }
        
        let addAction = UIAlertAction(title: String(localizationKey: "Add_Source.Button.Add"), style: .default, handler: { [weak self] _ in
            self?.dismiss(animated: true, completion: nil)
            guard let urlField = alert.textFields?[0],
                  let suiteField = alert.textFields?[1],
                  let componentField = alert.textFields?[2],
                  let url = URL(string: urlField.text ?? "") else { return }
            guard ["http","https"].contains(url.scheme?.lowercased()) && url.host != nil else { return }
            guard (urlField.text?.count ?? 0)>0, (suiteField.text?.count ?? 0)>0, (componentField.text?.count ?? 0)>0 else { return }
            guard let repo = RepoManager.shared.addDistRepo(url: url, suites: suiteField.text ?? "", components: componentField.text ?? "") else {
                return
            }
            self?.reloadData()
            self?.updateSingleRepo(repo)
        })
        alert.addAction(addAction)
        
        let cancel = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(cancel)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    #if !targetEnvironment(macCatalyst)
    @objc func addSource(_ sender: Any?) {
        // If URL(s) are copied, we ask the user if they want to add those.
        // Otherwise, we present the entry field dialog for the user to type a URL.
        if #available(iOS 14.0, *) {
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let pattern) where pattern.contains(.probableWebURL):
                        let newSources = UIPasteboard.general.newSources()
                        self.presentAddClipBoardPrompt(sources: newSources)
                    case .success, .failure:
                        self.presentAddSourceEntryField(url: nil)
                    }
                }
            }
        } else {
            let newSources = UIPasteboard.general.newSources()
            if newSources.isEmpty {
                self.presentAddSourceEntryField(url: nil)
            } else {
                self.presentAddClipBoardPrompt(sources: newSources)
            }
        }
    }
    #else
    @objc func addSource(_ sender: Any?) {
        self.presentAddSourceEntryField(url: nil)
    }
    #endif
    
    func handleSourceAdd(sources: [String], bypassFlagCheck: Bool) {

        var newRepos: [Repo] = []
        for source in sources {
            
            let parts = source.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter({$0.isEmpty==false})
            guard let url = URL(string: parts[0]) else { continue }
            
            if parts.count == 1 {
                let repos = RepoManager.shared.addRepos(with: [url])
                if !repos.isEmpty {
                    newRepos.append(contentsOf: repos)
                }
                continue
            }
            
            let suite = (parts.count > 1) ? parts[1] : "./"
            let components = (parts.count > 2) ? Array(parts[2...]) : []
            
            if let repo = RepoManager.shared.addDistRepo(url: url, suites: suite, components: components.joined(separator: " ")) {
                newRepos.append(repo)
            }
        }
        
        self.reloadData()
        self.updateSpecific(newRepos)
        
//        if newRepos.count > 1 {
//            self.updateSpecific(newRepos)
//            return
//        }
//
//        if newRepos.count == 1 {
//            let repo = newRepos[0]
//            guard let url = repo.url else { return }
//            EvanderNetworking.head(url: url.appendingPathComponent("Release")) { success in
//                if success {
//                    DispatchQueue.main.async {
//                        self.updateSingleRepo(repo)
//                    }
//                } else {
//                    DispatchQueue.main.async { [self] in
//                        let alert = UIAlertController(title: String(localizationKey: "Warning"),
//                                                      message: String(format: String(localizationKey: "Incorrect_Repo"), url.absoluteString),
//                                                      preferredStyle: .alert)
//                        alert.addAction(UIAlertAction(title: String(localizationKey: "Add_Source.Title"), style: .default, handler: { _ in
//                            self.updateSingleRepo(repo)
//                        }))
//                        alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
//                            RepoManager.shared.remove(repo: repo)
//                            self.reloadData()
//
//                            alert.dismiss(animated: true)
//                        }))
//                        self.present(alert, animated: true)
//                    }
//                }
//            }
//        }
    }
    
    // Smart Handling of pasted in sources
    @objc func textFieldDidChange(_ textField: UITextField) {
        guard var text = textField.text,
              text.count >= 15 else { return }
        if text.prefix(16).lowercased() == "https://https://" || text.prefix(15).lowercased() == "https://http://" {
            text = String(text.dropFirst(8))
        } else if text.prefix(15).lowercased() == "https://file://" {
            text = String(text.dropFirst(7))
        }
        
        textField.text = text
    }
}

extension SourcesViewController: UITableViewDataSource { // UITableViewDataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            self.reSortList()
            return sortedRepoList.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return (section == 1) ? String(localizationKey: "Repos") : nil
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let text = self.tableView(tableView, titleForHeaderInSection: section)
        let headerView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 36)))
        
        if let text = text {
            let headerBlur = UIToolbar(frame: headerView.bounds)
            headerView.tag = WHITE_BLUR_TAG
            headerBlur._hidesShadow = true
            headerBlur.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            headerView.addSubview(headerBlur)
            
            let titleView = SileoLabelView(frame: CGRect(x: 0, y: 0, width: 320, height: 28))
            titleView.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            titleView.text = text
            titleView.autoresizingMask = [.flexibleWidth]
            headerView.addSubview(titleView)
            
            titleView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                titleView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                titleView.heightAnchor.constraint(equalToConstant: titleView.frame.size.height)
                ])
            
//            let separatorView = SileoSeparatorView(frame: CGRect(x: 16, y: 35, width: 304, height: 1))
//            separatorView.autoresizingMask = .flexibleWidth
//            headerView.addSubview(separatorView)
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return 5
        case 1:
            return 44
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1 else { return UIView() }
        
        let footerView = SourcesTableViewFooter(reuseIdentifier: "Sileo.SourcesTableViewFooter")
        footerView.setCount(sortedRepoList.count)
        return footerView
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return (section == 0) ? 2 : 30
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "SourcesViewControllerCellidentifier") as? SourcesTableViewCell) ??
            SourcesTableViewCell(style: .subtitle, reuseIdentifier: "SourcesViewControllerCellidentifier")

        if indexPath.section == 0 {
            cell.repo = nil
        } else {
            cell.repo = sortedRepoList[indexPath.row]
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        55
    }
    
    private func updateFooterCount() {
        if let footerView = tableView.footerView(forSection: 1) as? SourcesTableViewFooter {
            footerView.setCount(sortedRepoList.count)
        }
    }
}

extension SourcesViewController: UITableViewDelegate { // UITableViewDelegate
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        indexPath.section > 0
    }
    
    #if !targetEnvironment(macCatalyst)
    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        action == #selector(UIResponderStandardEditActions.copy(_:)) 
    }

    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action != #selector(UIResponderStandardEditActions.copy(_:)) {
            return
        }
        
        let repo = sortedRepoList[indexPath.row]
        UIPasteboard.general.string = repo.aptSource
    }
    #else
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil,
                                   previewProvider: nil) { [weak self] _ in
            let copyAction = UIAction(title: "Copy") { [weak self] _ in
                let repo = self?.sortedRepoList[indexPath.row]
                UIPasteboard.general.string = repo?.aptSource
            }
            let deleteAction = UIAction(title: "Remove") { [weak self] _ in
                guard let strong = self else { return }
                strong.deleteRepo(at: indexPath)
            }
            let refreshAction = UIAction(title: "Refresh") { [weak self] _ in
                guard let strong = self else { return }
                let repo = strong.sortedRepoList[indexPath.row]
                strong.updateSpecific([repo])
            }
            return UIMenu(title: "", children: [copyAction, deleteAction, refreshAction])
        }
    }
    #endif

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if !self.canEditRow(indexPath: indexPath) {
            return .none
        }
        return .delete
    }
    
    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        self.canEditRow(indexPath: indexPath)
    }
    
    func tableViewSelectRowAt(tableView: UITableView, indexPath: IndexPath) {
        
        let categoryVC = self.controller(indexPath: indexPath)
        let navController = SileoNavigationController(rootViewController: categoryVC)
        self.splitViewController?.showDetailViewController(navController, sender: self)
        
        self.presentRepoUrl = categoryVC.repoContext?.url
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        tableViewSelectRowAt(tableView: tableView, indexPath: indexPath)
        
        self.detailedPageUserPresent = true
        
        if indexPath.section==0 && indexPath.row==0 {
            self.defaultPagePresent = true
        }

// should handle this when back to sources list
//        if self.splitViewController?.isCollapsed ?? false { // Only deselect the row if the split view contoller is not showing multiple
//            tableView.deselectRow(at: indexPath, animated: true)
//        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // We don't want to be able to delete the top section so we just return early here
        if indexPath.section == 0 { return nil }
        let refresh = UIContextualAction(style: .normal, title: String(localizationKey: "Refresh")) { _, _, completionHandler in
            self.updateSingleRepo(self.sortedRepoList[indexPath.row])
            completionHandler(true)
        }
        refresh.backgroundColor = .systemGreen
        if !self.canEditRow(indexPath: indexPath) {
            return UISwipeActionsConfiguration(actions: [refresh])
        }
        let remove = UIContextualAction(style: .destructive, title: String(localizationKey: "Remove")) { [weak self] _, _, completionHandler in
            self?.deleteRepo(at: indexPath)
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [remove, refresh])
    }
}

@available(iOS 14.0, *)
extension SourcesViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        NSLog("SileoLog: splitViewController:collapseSecondary \(presentRepoUrl) \(detailedPageUserPresent)")
        return !detailedPageUserPresent
    }
}

class TouchGestureRecognizer: UIGestureRecognizer {
    private var target: Any?
    private var action: Selector?
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        self.target = target
        self.action = action
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        self.state = .failed
        _ = (self.target as AnyObject).perform(action, with: nil)
    }
//    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
//        super.touchesMoved(touches, with: event)
//    }
//
//    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
//        super.touchesEnded(touches, with: event)
//    }
//    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
//        super.touchesCancelled(touches, with: event)
//    }
}

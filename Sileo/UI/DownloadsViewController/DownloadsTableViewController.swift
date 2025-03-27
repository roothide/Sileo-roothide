//
//  DownloadsTableViewController.swift
//  Sileo
//
//  Created by CoolStar on 8/3/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit
import Evander


class DownloadsTableViewController: SileoViewController {
    @IBOutlet private var footerView: UIView?
    @IBOutlet private var clearButton: UIButton? //clear queue button
    @IBOutlet private var confirmButton: UIButton?
    @IBOutlet private var footerViewHeight: NSLayoutConstraint?
    @IBOutlet private var tableView: UITableView?
    
    @IBOutlet private var detailsView: UIView?
    @IBOutlet private var detailsTextView: UITextView?
    @IBOutlet private var completeButton: DownloadConfirmButton?
    @IBOutlet private var showDetailsButton: UIButton?
    @IBOutlet private var hideDetailsButton: DownloadConfirmButton?
    @IBOutlet private var completeLaterButton: DownloadConfirmButton?
    @IBOutlet private var doneToTop: NSLayoutConstraint?
    @IBOutlet private var laterHeight: NSLayoutConstraint?
    @IBOutlet private var cancelDownload: DownloadConfirmButton?
    
    private var transitionController = false
    private var statusBarView: UIView?
    
    private var upgrades: [DownloadPackage] = []
    private var installations: [DownloadPackage] = []
    private var uninstallations: [DownloadPackage] = []
    private var installdeps: [DownloadPackage] = []
    private var uninstalldeps: [DownloadPackage] = []
    private var errors: ContiguousArray<APTBrokenPackage> = []
    
    private var actions = [Action]()
    
    private var isFired = false
    private var isInstalling = false
    private var isDownloading = false
    private var isFinishedInstalling = false
    
    private var returnButtonAction: APTWrapper.FINISH = .back
    private var refreshSileo = false
    private var hasErrored = false
    private var detailsAttributedString: NSMutableAttributedString?
    
    public var backgroundCallback: (() -> Void)?
    
    public class Action {
        
        // swiftlint:disable nesting
        public enum ActionType {
            case install
            case removal
        }
        
        var package: Package
        var type: ActionType
        var progressCounter: CGFloat = 0.0
        var status: String?
        weak var cell: DownloadsTableViewCell?
        
        public var progress: CGFloat {
            let progress = progressCounter / (type == .install ? 6.0 : 3.0)
            if progress > 1.0 {
                return 1.0
            } else {
                return progress
            }
        }
        
        init(package: Package, type: ActionType) {
            self.package = package
            self.type = type
            self.progressCounter = 0.0
        }
        
    }
    
    public override var prefersStatusBarHidden: Bool {
        return isFired
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.detailsTextView?.delegate = self
        
        let statusBarView = SileoRootView(frame: .zero)
        self.view.addSubview(statusBarView)
        self.statusBarView = statusBarView
        
        self.statusBarStyle = UIDevice.current.userInterfaceIdiom == .pad ? .default : .lightContent
        
        self.tableView?.separatorStyle = .none
        self.tableView?.separatorColor = UIColor(red: 234/255, green: 234/255, blue: 236/255, alpha: 1)
        self.tableView?.isEditing = true
        self.tableView?.clipsToBounds = true
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.tableView?.contentInsetAdjustmentBehavior = .never
            self.tableView?.contentInset = UIEdgeInsets(top: 43, left: 0, bottom: 0, right: 0)
        }
        
        confirmButton?.layer.cornerRadius = 10
        
        confirmButton?.setTitle(String(localizationKey: "Queue_Confirm_Button"), for: .normal)
        clearButton?.setTitle(String(localizationKey: "Queue_Clear_Button"), for: .normal)
        completeButton?.setTitle(String(localizationKey: "After_Install_Respring"), for: .normal)
        completeLaterButton?.setTitle(String(localizationKey: "After_Install_Respring_Later"), for: .normal)
        showDetailsButton?.setTitle(String(localizationKey: "Show_Install_Details"), for: .normal)
        hideDetailsButton?.setTitle(String(localizationKey: "Hide_Install_Details"), for: .normal)
        cancelDownload?.setTitle(String(localizationKey: "Queue_Cancel_Downloads"), for: .normal)
        
        completeButton?.layer.cornerRadius = 10
        completeLaterButton?.layer.cornerRadius = 10
        hideDetailsButton?.layer.cornerRadius = 10
        cancelDownload?.layer.cornerRadius = 10
        showDetailsButton?.isHidden = true
        
        //avoid button's backgroundColor changing when presenting a popover
        confirmButton?.tintAdjustmentMode = .normal
        clearButton?.tintAdjustmentMode = .normal
        completeButton?.tintAdjustmentMode = .normal
        completeLaterButton?.tintAdjustmentMode = .normal
        showDetailsButton?.tintAdjustmentMode = .normal
        hideDetailsButton?.tintAdjustmentMode = .normal
        cancelDownload?.tintAdjustmentMode = .normal
        
        tableView?.register(DownloadsTableViewCell.self, forCellReuseIdentifier: "DownloadsTableViewCell")
        
        self.reloadData()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard let tableView = self.tableView,
            let clearButton = self.clearButton,
            let confirmButton = self.confirmButton,
            let statusBarView = self.statusBarView else {
                return
        }
        
        statusBarView.frame = CGRect(origin: .zero, size: CGSize(width: self.view.bounds.width, height: tableView.safeAreaInsets.top))
        
        clearButton.tintColor = confirmButton.tintColor
        clearButton.isHighlighted = confirmButton.isHighlighted
        confirmButton.tintColor = UINavigationBar.appearance().tintColor
        confirmButton.isHighlighted = confirmButton.isHighlighted
        completeButton?.tintColor = UINavigationBar.appearance().tintColor
        completeButton?.isHighlighted = completeButton?.isHighlighted ?? false
        cancelDownload?.tintColor = UINavigationBar.appearance().tintColor
        cancelDownload?.isHighlighted = completeButton?.isHighlighted ?? false
        completeLaterButton?.tintColor = .clear
        completeLaterButton?.isHighlighted = completeLaterButton?.isHighlighted ?? false
        completeLaterButton?.setTitleColor(UINavigationBar.appearance().tintColor, for: .normal)
 
        hideDetailsButton?.tintColor = UINavigationBar.appearance().tintColor
        hideDetailsButton?.isHighlighted = hideDetailsButton?.isHighlighted ?? false
    }
    
    public func reloadData() {
        if !isInstalling {
            let manager = DownloadManager.shared
            let upgrades = manager.vars.upgrades.raw.sorted(by: { $0.package.name.lowercased() < $1.package.name.lowercased() })
            let installations = manager.vars.installations.raw.sorted(by: { $0.package.name.lowercased() < $1.package.name.lowercased() })
            let uninstallations = manager.vars.uninstallations.raw.sorted(by: { $0.package.name.lowercased() < $1.package.name.lowercased() })
            let installdeps = manager.vars.installdeps.raw.sorted(by: { $0.package.name.lowercased() < $1.package.name.lowercased() })
            let uninstalldeps = manager.vars.uninstalldeps.raw.sorted(by: { $0.package.name.lowercased() < $1.package.name.lowercased() })
            let errors = manager.vars.errors.raw
            
            self.upgrades = upgrades
            self.installations = installations
            self.uninstallations = uninstallations
            self.installdeps = installdeps
            self.uninstalldeps = uninstalldeps
            self.errors = ContiguousArray<APTBrokenPackage>(errors)
        }
        self.tableView?.reloadData()
        self.reloadControlsOnly()
    }

    //update state/UI and start the installation (if applicable)
    public func reloadControlsOnly() {
        NSLog("SileoLog: reloadControlsOnly")
//        Thread.callStackSymbols.forEach{NSLog("SileoLog: reloadControlsOnly callstack=\($0)")}

        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.reloadControlsOnly()
            }
            return
        }
        
        cancelDownload?.isHidden = !isDownloading
        if isFinishedInstalling {
            clearButton?.isHidden = true
            confirmButton?.isHidden = true
            showDetailsButton?.isHidden = false
            completeButton?.isHidden = false
            completeLaterButton?.isHidden = false
            if completeLaterButton?.alpha == 0 {
                doneToTop?.constant = 0
                laterHeight?.constant = 0
                FRUIView.animate(withDuration: 0.25) {
                    self.footerViewHeight?.constant = 125
                    self.footerView?.alpha = 1
                }
            } else {
                doneToTop?.constant = 15
                laterHeight?.constant = 50
                FRUIView.animate(withDuration: 0.25) {
                    self.footerViewHeight?.constant = 190
                    self.footerView?.alpha = 1
                }
            }
            return
        } else {
            clearButton?.isHidden = false
            confirmButton?.isHidden = false
            showDetailsButton?.isHidden = true
            completeButton?.isHidden = true
            completeLaterButton?.isHidden = true
        }
        let manager = DownloadManager.shared
        if manager.operationCount() > 0 && !manager.queueRunning && manager.vars.errors.isEmpty {
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 128
                self.footerView?.alpha = 1
            }
        } else if isDownloading {
            clearButton?.isHidden = true
            confirmButton?.isHidden = true
            showDetailsButton?.isHidden = true
            completeButton?.isHidden = true
            completeLaterButton?.isHidden = true
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 90
                self.footerView?.alpha = 1
            }
        } else {
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 0
                self.footerView?.alpha = 0
            }
        }
        if manager.vars.errors.isEmpty {
            self.confirmButton?.isEnabled = true
            self.confirmButton?.alpha = 1
        } else {
            self.confirmButton?.isEnabled = false
            self.confirmButton?.alpha = 0.5
        }
    }
    
    private func checkReady() {
        let manager = DownloadManager.shared
        if manager.operationCount() > 0 && manager.verifyComplete() && manager.queueRunning && manager.vars.errors.isEmpty {
            isDownloading = false
            cancelDownload?.isHidden = true
            FRUIView.animate(withDuration: 0.25) {
                self.footerViewHeight?.constant = 0
                self.footerView?.alpha = 0
            }
            transferToAction()
            TabBarController.singleton?.presentPopupController()
        }
    }
    
    public func updateDownloadStatus(download: Download) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [self] in
                self.updateDownloadStatus(download: download)
            }
            return
        }
        
        NSLog("SileoLog: updateDownloadStatus \(download.package.package) download=\(download),\(download.progress)")
        
        guard download.session == DownloadManager.shared.currentDownloadSession else {
            return
        }
        
        for cell in tableView?.loadedCells ?? [] {
            if let cell = cell as? DownloadsTableViewCell {
                if cell.package?.package == download.package.package {
                    if cell.download == nil {
                        cell.download = download
                    }
                    cell.updateStatus()
                    TabBarController.singleton?.updatePopup()
                    break
                }
            }
        }
        
        self.checkReady()
    }
    
    @IBAction public func cancelDownload(_ sender: Any?) {
        NSLog("SileoLog: ***cancelDownload \(sender)")
        if !Thread.isMainThread {
            fatalError("Wtf are you doing")
        }
        
        if let sender = sender as? UIButton, sender.isHidden {
            return //UIKit bug: https://stackoverflow.com/questions/37916952/ios-why-does-hidden-button-still-receive-tap-events/37918283#37918283
        }
        
        isInstalling = false
        isDownloading = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        self.actions.removeAll()
        self.tableView?.setEditing(true, animated: true)
        
        DownloadManager.shared.queueRunning = false
        DownloadManager.shared.cancelDownloads()
        NotificationCenter.default.post(name: DownloadManager.lockStateChangeNotification, object: nil)
        
        self.reloadData()
        TabBarController.singleton?.updatePopup()
    }
    
    @IBAction private func cancelQueued(_ sender: Any?) {
        NSLog("SileoLog: cancelQueued")
        isInstalling = false
        isDownloading = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        self.actions.removeAll()
        
        DownloadManager.shared.queueRunning = false
        NotificationCenter.default.post(name: DownloadManager.lockStateChangeNotification, object: nil)
        
        DownloadManager.aptQueue.async {
            DownloadManager.shared.removeAllItems()
            DownloadManager.shared.reloadData(recheckPackages: true)
        }

        TabBarController.singleton?.dismissPopupController(completion: { [self] in
            tableView?.setEditing(true, animated: true)
        })
        TabBarController.singleton?.updatePopup(bypass: true)
    }
    
    @IBAction public func confirmQueued(_ sender: Any?) {
        NSLog("SileoLog: confirmQueued(\(sender))")
        if sender != nil {
            let actions = uninstallations + uninstalldeps
            let essentialPackages = actions.map { $0.package }.filter { DownloadManager.shared.isEssential($0) }
            if essentialPackages.isEmpty {
                return confirmQueued(nil)
            }
            let formatPackages = essentialPackages.map { "\n\($0.name ?? $0.package)" }.joined()
            let message = String(format: String(localizationKey: "Essential_Warning"), formatPackages)
            let alert = UIAlertController(title: String(localizationKey: "Warning"),
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .default, handler: { _ in
                alert.dismiss(animated: true)
            }))
            alert.addAction(UIAlertAction(title: String(localizationKey: "Dangerous_Repo.Last_Chance.Continue"), style: .destructive, handler: { _ in
                self.confirmQueued(nil)
            }))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        isDownloading = true
        
        DownloadManager.shared.aptRunning = false
        DownloadManager.shared.aptFinished = false
        DownloadManager.shared.queueRunning = true
        DownloadManager.shared.currentDownloads = 0
        NotificationCenter.default.post(name: DownloadManager.lockStateChangeNotification, object: nil)
        
        NSLog("SileoLog: startMoreDownloads (confirmQueued)")
        DownloadManager.shared.startDownloads()
        TabBarController.singleton?.updatePopup()
        self.reloadData()
        self.checkReady()
        
        tableView?.setEditing(false, animated: true)
        for cell in tableView?.visibleCells ?? [] {
            if let cell = cell as? DownloadsTableViewCell {
                cell.setEditing(false, animated: true)
            }
        }
    }
    
    override func accessibilityPerformEscape() -> Bool {
        TabBarController.singleton?.dismissPopupController()
        return true
    }
    
    private func transferToAction() {
        NSLog("SileoLog: transferToAction \(isInstalling)")
        if isInstalling {
            return
        }
        isInstalling = true
        var earlyBreak = false
        if UIApplication.shared.applicationState == .background || UIApplication.shared.applicationState == .inactive, let completion = backgroundCallback {
            earlyBreak = true
            completion()
        }
        
        detailsAttributedString = NSMutableAttributedString(string: "")
        let installs = installations + upgrades + installdeps
        if UserDefaults.standard.bool(forKey: "CanisterIngest", fallback: false) {
            CanisterResolver.shared.ingest(packages: installs.map { $0.package })
        }
        let removals = uninstallations + uninstalldeps
        self.actions += installs.map { Action(package: $0.package, type: .install) }
        self.actions += removals.map { Action(package: $0.package, type: .removal) }
        
        for cell in tableView?.loadedCells ?? [] {
            if let cell = cell as? DownloadsTableViewCell {
                if let action = actions.first(where: { $0.package.package == cell.package?.package }) {
                    cell.action = action
                }
            }
        }
        
        if !earlyBreak {
            //always startInstall after UI update is complete
//            DispatchQueue.main.async {
                self.startAction()
//            }
        }
    }
    
    private func statusWork(package: String, status: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.statusWork(package: package, status: status)
            }
            return
        }
        guard let action = actions.first(where: { $0.package.package == package }) else { return }
        action.progressCounter += 1
        let ending = "(\(DPKGArchitecture.Architecture.roothide.rawValue))"
        if action.package.tags.contains(.roothide) && status.hasSuffix(ending) {
            if var origArch = action.package.origArchitecture {
                action.status = status.replacingOccurrences(of: ending, with: "(\(origArch))")
            } else {
                action.status = status.replacingOccurrences(of: ending, with: "")
            }
        } else {
            action.status = status
        }
        NSLog("SileoLog: action=\(action) cell=\(action.cell)")
        action.cell?.updateStatus()
    }
    
    private func queueCompleted() {
        isInstalling = false
        isFinishedInstalling = false
        returnButtonAction = .back
        refreshSileo = false
        hasErrored = false
        actions.removeAll()

        TabBarController.singleton?.popupContent?.popupInteractionStyle = .default
        DownloadManager.shared.queueRunning = false
        DownloadManager.aptQueue.async {
            DownloadManager.shared.removeAllItems()
            DownloadManager.shared.reloadData(recheckPackages: true)
        }
        TabBarController.singleton?.dismissPopupController(completion: { [self] in
            tableView?.setEditing(true, animated: true)
        })
        TabBarController.singleton?.updatePopup(bypass: true)
    }
    
    @IBAction private func completeButtonTapped(_ sender: Any?) {
        if returnButtonAction == .back && !refreshSileo {
            queueCompleted()
            return
        }
        
        isFired = true
        setNeedsStatusBarAppearanceUpdate()
        
        let window = UIApplication.shared.keyWindow

        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) {
            window?.alpha = 0
            window?.transform = .init(scaleX: 0.9, y: 0.9)
        }

        // When the animation has finished, fire the dumb respring code
        animator.addCompletion { _ in
            
            //1: at least since iOS16, "uicache -p sileo.app" will kill the sileo process
            //2: rebooting userspace immediately after executing uicache may cause jailbreak apps to disappear
            
            switch self.returnButtonAction {
                case .uicache:
                    spawnAsRoot(args:[jbroot("/usr/bin/uicache"), "-a"])
                
                case .reload, .restart:
                    spawnAsRoot(args:[jbroot("/usr/bin/sbreload")])
                
                case .reboot, .usreboot:
                    spawnAsRoot(args:[jbroot("/usr/bin/sync")])
                    spawnAsRoot(args:[jbroot("/usr/bin/launchctl"), "reboot", "userspace"])
                
                case .reopen:
                    if self.refreshSileo {
                        UserDefaults.standard.setValue(false, forKey: "uicacheRequired")
                        UserDefaults.standard.synchronize()
                        spawnAsRoot(args:[jbroot("/usr/bin/uicache"), "-p", rootfs(Bundle.main.bundlePath)])
                    }
                    exit(0)
                
                default:
                    if self.refreshSileo {
                        UserDefaults.standard.setValue(false, forKey: "uicacheRequired")
                        UserDefaults.standard.synchronize()
                        spawnAsRoot(args:[jbroot("/usr/bin/uicache"), "-p", rootfs(Bundle.main.bundlePath)])
                        exit(0)
                    }
            }
        }
        // Fire the animation
        animator.startAnimation()
    }
    
    @IBAction private func completeLaterButtonTapped(_ sender: Any?) {
        queueCompleted()
    }
    
    private func transform(attributedString: NSMutableAttributedString) -> NSMutableAttributedString {
        let font = UIFont(name: "Menlo-Regular", size: 12) ?? UIFont.systemFont(ofSize: 12)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        
        attributedString.addAttributes([
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ], range: NSRange(location: 0, length: attributedString.length))
        return attributedString
    }
    
    private func startAction() {
        NSLog("SileoLog: startAction")
        func shouldShow(_ finish: APTWrapper.FINISH) -> Bool {
            finish == .reload || finish == .restart || finish == .reboot || finish == .usreboot
        }
        
        if let detailsAttributedString = self.detailsAttributedString {
            detailsTextView?.attributedText = self.transform(attributedString: detailsAttributedString)
        }
        
        DownloadManager.shared.aptRunning = true
        DownloadManager.shared.aptFinished = false
        
        TabBarController.singleton?.updatePopup()

        APTWrapper.performOperations(installs: installations + upgrades, removals: uninstallations, installDeps: installdeps, progressCallback: { _, statusValid, statusReadable, package in
            NSLog("SileoLog: progressCallback \(statusValid) \(package) \(statusReadable)")
            if statusValid {
                self.statusWork(package: package, status: statusReadable)
            }
        }, outputCallback: { output, pipe in
            NSLog("SileoLog: apt outputCallback \(pipe):\(output)")
            var textColor = Dusk.foregroundColor
            if pipe == STDERR_FILENO {
                textColor = Dusk.errorColor
                self.hasErrored = true
            }
            if pipe == APTWrapper.debugFD {
                textColor = Dusk.debugColor
            }
            
            if output.prefix(2) == "W:" || output.contains("dpkg: warning") {
                textColor = Dusk.warningColor
            }
            
            let substring = NSMutableAttributedString(string: output, attributes: [NSAttributedString.Key.foregroundColor: textColor])
            DispatchQueue.main.async {
                self.detailsAttributedString?.append(substring)
                
                guard let detailsAttributedString = self.detailsAttributedString else {
                    return
                }
                
                self.detailsTextView?.attributedText = self.transform(attributedString: detailsAttributedString)
                
                self.detailsTextView?.scrollRangeToVisible(NSRange(location: detailsAttributedString.string.count - 1, length: 1))
            }
        }, completionCallback: { status, finish, refresh in
            NSLog("SileoLog: apt completionCallback \(status) \(finish) \(refresh)")
            PackageListManager.shared.reloadInstalled()
            DispatchQueue.main.async {
                
                DownloadManager.shared.aptRunning = false
                DownloadManager.shared.aptFinished = true
                
                NotificationCenter.default.post(name: PackageListManager.stateChange, object: nil)
                NotificationCenter.default.post(name: PackageListManager.installChange, object: nil)
                let rawUpdates = PackageListManager.shared.availableUpdates()
                let updatesNotIgnored = rawUpdates.filter({ $0.1?.wantInfo != .hold })
                UIApplication.shared.applicationIconBadgeNumber = updatesNotIgnored.count
                
                _ = self.actions.map { $0.progressCounter = 7 }
                self.tableView?.reloadData()
                
                self.returnButtonAction = finish
                self.refreshSileo = refresh
                self.updateCompleteButton()
                self.completeButton?.alpha = 1
                self.showDetailsButton?.isHidden = false
                self.completeLaterButton?.alpha = shouldShow(finish) ? 1 : 0
                
                self.isFinishedInstalling = true
                self.reloadControlsOnly()
                
                TabBarController.singleton?.updatePopup()
                
                if UserDefaults.standard.bool(forKey: "AlwaysShowLog") || self.hasErrored {
                    self.showDetails(nil)
                }
                else
                if (UserDefaults.standard.bool(forKey: "AutoComplete") && !self.hasErrored) // || !(TabBarController.singleton?.popupIsPresented ?? false)
                {
                    self.completeButtonTapped(nil)
                }
                NotificationCenter.default.post(name: NSNotification.Name("Sileo.CompleteInstall"), object: nil)
            }
        })
    }
        
    private func updateCompleteButton() {
        switch returnButtonAction {
        case .back:
            if refreshSileo {
                completeButton?.setTitle(String(localizationKey: "After_Install_Relaunch"), for: .normal)
                completeLaterButton?.setTitle(String(localizationKey: "After_Install_Relaunch_Later"), for: .normal)
            } else {
                completeButton?.setTitle(String(localizationKey: "Done"), for: .normal)
            }
        case .uicache:
            completeButton?.setTitle(String(localizationKey: "Refresh"), for: .normal)
        case .reopen:
            completeButton?.setTitle(String(localizationKey: "After_Install_Relaunch"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Relaunch_Later"), for: .normal)
        case .reload, .restart:
            completeButton?.setTitle(String(localizationKey: "After_Install_Respring"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Respring_Later"), for: .normal)
        case .reboot, .usreboot:
            completeButton?.setTitle(String(localizationKey: "After_Install_Reboot"), for: .normal)
            completeLaterButton?.setTitle(String(localizationKey: "After_Install_Reboot_Later"), for: .normal)
        }
        
        if refreshSileo {
            UserDefaults.standard.setValue(true, forKey: "uicacheRequired")
            UserDefaults.standard.synchronize()
        }
    }
    
    @IBAction private func showDetails(_ sender: Any?) {
        guard let detailsView = self.detailsView else {
            return
        }
        detailsView.alpha = 0
        detailsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        detailsView.frame = self.view.bounds
        
        self.view.addSubview(detailsView)
        
        self.view.bringSubviewToFront(detailsView)
        FRUIView.animate(withDuration: 0.25) {
            self.detailsView?.alpha = 1
        
            self.statusBarStyle = .lightContent
            
            TabBarController.singleton?.popupContentView.popupCloseButton.isHidden = true
        }
    }
    
    @IBAction private func hideDetails(_ sender: Any?) {
        FRUIView.animate(withDuration: 0.25, animations: {
            self.detailsView?.alpha = 0
            
            self.statusBarStyle = UIDevice.current.userInterfaceIdiom == .pad ? .default : .lightContent
            
            TabBarController.singleton?.popupContentView.popupCloseButton.isHidden = false
        }, completion: { _ in
            self.detailsView?.removeFromSuperview()
        })
    }

}

extension DownloadsTableViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        6
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return installations.count + installdeps.count
        case 1:
            return uninstallations.count + uninstalldeps.count
        case 2:
            return upgrades.count
        case 3:
            return errors.count
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView.numberOfRows(inSection: section) == 0 {
            return nil
        }
        switch section {
        case 0:
            return String(localizationKey: "Queued_Install_Heading")
        case 1:
            return String(localizationKey: "Queued_Uninstall_Heading")
        case 2:
            return String(localizationKey: "Queued_Update_Heading")
        case 3:
            return String(localizationKey: "Download_Errors_Heading")
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if (self.tableView?.numberOfRows(inSection: section) ?? 0) > 0 {
            let headerView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 36)))
            
            let backgroundView = SileoRootView(frame: CGRect(x: 0, y: -24, width: 320, height: 60))
            backgroundView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            headerView.addSubview(backgroundView)
            
            if let text = self.tableView(tableView, titleForHeaderInSection: section) {
                let titleView = SileoLabelView(frame: CGRect(x: 0, y: 0, width: 320, height: 28))
                titleView.font = UIFont.systemFont(ofSize: 22, weight: .bold)
                titleView.text = text
                titleView.autoresizingMask = .flexibleWidth
                headerView.addSubview(titleView)
                
                titleView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    titleView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                    titleView.heightAnchor.constraint(equalToConstant: titleView.frame.size.height)
                    ])
                
                let separatorView = SileoSeparatorView(frame: CGRect(x: 16, y: 35, width: 304, height: 1))
                separatorView.autoresizingMask = .flexibleWidth
                headerView.addSubview(separatorView)
            }
            return headerView
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.tableView(tableView, numberOfRowsInSection: section) > 0 {
            return 36
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView() // do not show extraneous tableview separators
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        8
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        58
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "DownloadsTableViewCell"
        // swiftlint:disable force_cast
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! DownloadsTableViewCell
        if indexPath.section == 3 {
            // Error listing
            let error = errors[indexPath.row]
            let allpackages = upgrades+installations+installdeps+uninstallations+uninstalldeps
            if let package = allpackages.first(where: { $0.package.package == error.packageID }) {
                cell.package = package.package
            } else {
                cell.package = Package(package: error.packageID, version: "-1")
            }
            var description = ""
            for (index, conflict) in error.conflictingPackages.enumerated() {
                description += "\(conflict.conflict.rawValue) \(conflict.package)\(index == error.conflictingPackages.count - 1 ? "" : ", ")"
            }
            cell.errorDescription = description
        } else {
            // Normal operation listing
            var array: [DownloadPackage] = []
            switch indexPath.section {
            case 0:
                array = installations + installdeps
            case 1:
                array = uninstallations + uninstalldeps
            case 2:
                array = upgrades
            default:
                break
            }
            
            let package = array[indexPath.row].package
            
            cell.package = package
            cell.download = DownloadManager.shared.queuedDownload(package: package.package)
            cell.action = actions.first(where: { $0.package.package == package.package })
        }
        cell.updateStatus()
        return cell
    }
}

extension DownloadsTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 3 || isInstalling || isDownloading {
            return false
        }
        var array: [DownloadPackage] = []
        switch indexPath.section {
        case 0:
            array = installations
        case 1:
            array = uninstallations
        case 2:
            array = upgrades
        default:
            break
        }
        if indexPath.row >= array.count {
            return false
        }
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            var queue: DownloadManagerQueue = .none
            var array: [DownloadPackage] = []
            switch indexPath.section {
            case 0:
                array = installations
                queue = .installations
                installations.remove(at: indexPath.row)
            case 1:
                array = uninstallations
                queue = .uninstallations
                uninstallations.remove(at: indexPath.row)
            case 2:
                array = upgrades
                queue = .upgrades
                upgrades.remove(at: indexPath.row)
            default:
                break
            }
            if indexPath.section == 3 || indexPath.row >= array.count {
                fatalError("Invalid section/row (not editable)")
            }
            
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            let downloadManager = DownloadManager.shared
            downloadManager.remove(downloadPackage: array[indexPath.row], queue: queue)
            downloadManager.reloadData(recheckPackages: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension DownloadsTableViewController: UITextViewDelegate {
    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool
    {
        if action == #selector(selectAll(_:)) {
            return true
        } else {
            return false
        }
    }
    
    override func selectAll(_ sender: Any?) {
        detailsTextView?.selectAll(sender)
    }
}

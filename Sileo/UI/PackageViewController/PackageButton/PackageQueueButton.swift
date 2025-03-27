//
//  PackageQueueButton.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

protocol PackageQueueButtonDataProvider: AnyObject {
    
}

class PackageQueueButton: PackageButton {
    
    static let actionPerformedNotification = Notification.Name("actionPerformedNotification")

    public weak var viewControllerForPresentation: UIViewController?
    public var package: Package? {
        didSet {
            DispatchQueue.main.async {
                if let package=self.package, package.commercial {
                    self.paymentInfo = PaymentPackageInfo(price: String(localizationKey: "Package_Paid"), purchased: false, available: true)
                    //paymentInfo->didSet->self.updateInfo()
                } else {
                    self.updateInfo()
                }
            }
        }
    }

    public var paymentInfo: PaymentPackageInfo? {
        didSet {
            DispatchQueue.main.async {
                self.updateInfo()
            }
        }
    }
    
    public var overrideTitle: String = ""
    
    private var installedPackage: Package?
    
    override func setup() {
        super.setup()
        
        self.updateButton(title: String(localizationKey: "Package_Get_Action"))
        self.addTarget(self, action: #selector(PackageQueueButton.buttonTapped(_:)), for: .touchUpInside)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageQueueButton.updateInfo),
                                               name: PackageListManager.stateChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageQueueButton.updateInfo),
                                               name: DownloadManager.lockStateChangeNotification,
                                               object: nil)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(PackageQueueButton.showVersionPrompt(_:)))
        self.addGestureRecognizer(longPressGesture)
    }

    @objc func showVersionPrompt(_ sender: Any?) {
        guard let package = package, !(package.isProvisional ?? false) else {
            return
        }
        let versionPrompt = UIAlertController(title: String(localizationKey: "Select Version"),
                                                message: String(localizationKey: "Select the version of the package to install"),
                                                preferredStyle: .actionSheet)
        
        var allPackages: [Package] = []
        
        if package.fromStatusFile {
            for repo in RepoManager.shared.repoList {
                allPackages += repo.allVersions(identifier: package.package, ignoreArch: true)
            }
            allPackages = PackageListManager.shared.sortPackages(packages: allPackages, search: nil)
        } else {
            allPackages = package.allVersions(ignoreArch: true).sorted(by: { obj1, obj2 -> Bool in
                if DpkgWrapper.isVersion(obj1.version, greaterThan: obj2.version) {
                    return true
                }
                return false
            })
        }

        var versioncount=0
        for versionPackage in allPackages {
            let title = package.fromStatusFile ? "\t\(versionPackage.version) • \(versionPackage.sourceRepo!.displayName)" : versionPackage.version
            let versionAction = UIAlertAction(title: title, style: .default, handler: { (_: UIAlertAction) in
                self.requestQueuePackage(package: versionPackage, queue: .installations)
            })
            if package.fromStatusFile { versionAction.setValue(CATextLayerAlignmentMode.left, forKey: "titleTextAlignment") }
            if !checkRootHide(versionPackage) { versionAction.setValue(UIColor.gray, forKey: "titleTextColor") }
            versionPrompt.addAction(versionAction)
            versioncount += 1
        }
        
        if versioncount==0 { return }

        let cancelAction = UIAlertAction(title: String(localizationKey: "Package_Cancel_Action"), style: .cancel, handler: nil)
        versionPrompt.addAction(cancelAction)
        if UIDevice.current.userInterfaceIdiom == .pad {
            versionPrompt.popoverPresentationController?.sourceView = self
        }
        let tintColor = self.tintColor
        versionPrompt.view.tintColor = tintColor
        viewControllerForPresentation?.present(versionPrompt, animated: true, completion: {
            versionPrompt.view.tintColor = tintColor
        })
    }
    
    @objc func updateInfo() {
//        NSLog("SileoLog: updateInfo package=\(package?.package)")
        guard let package = package else {
            self.updateButton(title: String(localizationKey: "Package_Get_Action"))
            self.isEnabled = false
            return
        }

        if package.isProvisional ?? false {
            self.updateButton(title: String(localizationKey: "Add_Source.Title"))
            return
        } else if !package.fromStatusFile && package.sourceRepo==nil && package.local_deb==nil {
            self.updateButton(title: String(localizationKey: "Package_Get_Action"))
            self.isEnabled = false
            return
        }
        
        installedPackage = PackageListManager.shared.installedPackage(identifier: package.package)
        let purchased = paymentInfo?.purchased ?? false
        
        //Competition with DependencyResolverAccelerator.shared.preflightInstalled()->init(){4 spawns} for aptQueue causes a two second lag
        let queueFound = DownloadManager.shared.find(package: package)
        
        if !overrideTitle.isEmpty {
            self.updateButton(title: overrideTitle)
        } else if queueFound != .none {
            self.updateButton(title: String(localizationKey: "Package_Queue_Action"))
        } else if installedPackage != nil {
            self.updateButton(title: String(localizationKey: "Package_Modify_Action"))
        } else if let price = paymentInfo?.price, package.commercial && !purchased {
            self.updateButton(title: price)
        } else {
            self.updateButton(title: String(localizationKey: "Package_Get_Action"))
            self.isProminent = true
        }
        
        self.isEnabled = !DownloadManager.shared.queueRunning
    }
    
    func updateButton(title: String) {
        self.setTitle(title.uppercased(), for: .normal)
    }
    
    func actionItems() -> [CSActionItem] {
        guard let package = self.package else {
                return []
        }
        if package.isProvisional ?? false {
            guard let source = package.source else {
                return []
            }
            let action = CSActionItem(title: String(localizationKey: "Add_Source.Title"),
                                      image: UIImage(systemNameOrNil: "square.and.arrow.down"),
                                      style: .default) {
                self.hapticResponse()
                self.addRepo(source)
                CanisterResolver.shared.queuePackage(package)
            }
            return [action]
        }
        var actionItems: [CSActionItem] = []

        let downloadManager = DownloadManager.shared
        
        if downloadManager.queueRunning { return [] }

        //self.installedPackage may not be ready yet
        if let installedPackage = PackageListManager.shared.installedPackage(identifier: package.package) {
            if !package.commercial || (paymentInfo?.available ?? false) {
                var repo: Repo?
                for repoEntry in RepoManager.shared.repoList where
                    repoEntry.rawEntry == package.sourceFile {
                    repo = repoEntry
                }
                if package.filename != nil && repo != nil {
                    if DpkgWrapper.isVersion(package.version, greaterThan: installedPackage.version) {
                        let action = CSActionItem(title: String(localizationKey: "Package_Upgrade_Action"),
                                                  image: UIImage(systemNameOrNil: "icloud.and.arrow.down"),
                                                  style: .default) {
                            self.hapticResponse()
                            self.requestQueuePackage(package: package, queue: .upgrades)
                        }
                        actionItems.append(action)
                    } else if package.version == installedPackage.version {
                        let action = CSActionItem(title: String(localizationKey: "Package_Reinstall_Action"),
                                                  image: UIImage(systemNameOrNil: "arrow.clockwise.circle"),
                                                  style: .default) {
                            self.hapticResponse()
                            self.requestQueuePackage(package: package, queue: .installations)
                        }
                        actionItems.append(action)
                    }
                }
            }
            let action = CSActionItem(title: String(localizationKey: "Package_Uninstall_Action"),
                                      image: UIImage(systemNameOrNil: "trash.circle"),
                                      style: .destructive) {
                self.hapticResponse()
                self.requestQueuePackage(package: package, queue: .uninstallations)
            }
            actionItems.append(action)
        } else if !package.fromStatusFile {
            let action = CSActionItem(title: String(localizationKey: "Package_Get_Action"),
                                      image: UIImage(systemNameOrNil: "square.and.arrow.down"),
                                      style: .default) {
                
                NSLog("SileoLog: Package_Get_Action0 \(package.package) \(package.sourceRepo) \(package.commercial) \(self.paymentInfo?.purchased)")
                self.hapticResponse()
                self.requestQueuePackage(package: package, queue: .installations)
            }
            actionItems.append(action)
        }
    
        let copyBundleIDAction = CSActionItem(title: String(localizationKey: "Copy_ID"), image: .init(systemNameOrNil: "doc.on.doc"), style: .default) {
            UIPasteboard.general.string = package.package
        }
        actionItems.append(copyBundleIDAction)
        
        return actionItems
    }
    
    private func addRepo(_ source: ProvisionalRepo) {
        // sometimes self.window may be nil if QueueButton os not being shown
        //if let tabBarController = self.window?.rootViewController as? UITabBarController,
        if let tabBarController = TabBarController.singleton,
            let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
              let sourcesNavNV = sourcesSVC.viewControllers[0] as? SileoNavigationController {
              tabBarController.selectedViewController = sourcesSVC
              if let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController {
                  if source.suite == "./" {
                      sourcesVC.presentAddSourceEntryField(url: source.uri)
                  } else {
                      sourcesVC.addDistRepo(string: source.uri.absoluteString, suites: source.suite, components: source.component)
                  }
              }
        }
    }
    
    private func handleButtonPress(_ package: Package, _ check: Bool = true) {
        if check {
            if package.isProvisional ?? false {
                guard let source = package.source else { return }
                self.addRepo(source)
                CanisterResolver.shared.queuePackage(package)
                return
            }
        }
        if DownloadManager.shared.queueRunning {
            TabBarController.singleton?.presentPopupController()
            return
        }
        self.hapticResponse()
        let downloadManager = DownloadManager.shared
        let queueFound = downloadManager.find(package: package)
        if queueFound != .none {
            // but it's a already queued! user changed their mind about installing this new package => nuke it from the queue
            TabBarController.singleton?.presentPopupController()
            downloadManager.reloadData(recheckPackages: true)
            
            NotificationCenter.default.post(name: PackageQueueButton.actionPerformedNotification, object: nil)
                
        } else if let installedPackage = installedPackage {
            NSLog("SileoLog: \(package.package) commercial=\(package.commercial) purchased=\(paymentInfo?.purchased) price=\(paymentInfo?.price) available=\(paymentInfo?.available)")
            // road clear to modify an installed package, now we gotta decide what modification
            let downloadPopup: UIAlertController! = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
//            if !package.commercial || (paymentInfo?.available ?? false) {
                var repo: Repo?
                for repoEntry in RepoManager.shared.repoList where
                    repoEntry.rawEntry == package.sourceFile {
                    repo = repoEntry
                 }
                if !package.fromStatusFile {
                    if DpkgWrapper.isVersion(package.version, greaterThan: installedPackage.version) {
                        let upgradeAction = UIAlertAction(title: String(localizationKey: "Package_Upgrade_Action"), style: .default) { _ in
                            self.requestQueuePackage(package: package, queue: .upgrades)
                        }
                        downloadPopup.addAction(upgradeAction)
                    } else {
                        let reinstallAction = UIAlertAction(title: String(localizationKey: "Package_Reinstall_Action"), style: .default) { _ in
                            if package.version == installedPackage.version {
                                self.requestQueuePackage(package: package, queue: .installations)
                            } else {
                                downloadPopup.dismiss(animated: false) {
                                    self.showVersionPrompt(nil)
                                }
                            }
                        }
                        downloadPopup.addAction(reinstallAction)
                    }
                } else if let hasRepoPackage = PackageListManager.shared.newestPackage(identifier: package.package) {
                    let reinstallAction = UIAlertAction(title: String(localizationKey: "Package_Reinstall_Action"), style: .default) { _ in
                        downloadPopup.dismiss(animated: false) {
                            self.showVersionPrompt(nil)
                        }
                    }
                    downloadPopup.addAction(reinstallAction)
                }
//            }

            let removeAction = UIAlertAction(title: String(localizationKey: "Package_Uninstall_Action"), style: .default, handler: { _ in
                self.requestQueuePackage(package: package, queue: .uninstallations)
            })
            downloadPopup.addAction(removeAction)
            let cancelAction: UIAlertAction! = UIAlertAction(title: String(localizationKey: "Package_Cancel_Action"), style: .cancel)
            downloadPopup.addAction(cancelAction)
            if UIDevice.current.userInterfaceIdiom == .pad {
                downloadPopup.popoverPresentationController?.sourceView = self
            }
            let tintColor: UIColor! = self.tintColor
            if tintColor != nil {
                downloadPopup.view.tintColor = tintColor
            }
            self.viewControllerForPresentation?.present(downloadPopup, animated: true, completion: {
                if tintColor != nil {
                    downloadPopup.view.tintColor = tintColor
                }
            })
        } else if package.sourceRepo != nil || package.local_deb != nil {
            self.requestQueuePackage(package: package, queue: .installations)
        } else {
            self.showVersionPrompt(nil)
        }
    }
    
    @objc func buttonTapped(_ sender: Any?) {
        guard let package = self.package else {
            return
        }
        self.handleButtonPress(package)
    }
    
    private func queuePackage(_ package: Package, _ queue: DownloadManagerQueue)
    {
        if DownloadManager.shared.queueRunning { return }
        DownloadManager.shared.add(package: package, queue: queue) {
            DownloadManager.shared.reloadData(recheckPackages: true)
        }
        NotificationCenter.default.post(name: PackageQueueButton.actionPerformedNotification, object: nil)
    }
    
    private var hasPurchased: Bool {
        guard let paymentInfo=self.paymentInfo else {
            return false
        }
        return paymentInfo.purchased && paymentInfo.available
    }
    
    private func requestQueuePackage(package: Package, queue: DownloadManagerQueue)
    {
        NSLog("SileoLog: requestQueuePackage \(package.package)=\(package.version) commercial=\(package.commercial) \(package.sourceRepo):\(package.sourceRepo?.rawURL) purchased=\(self.hasPurchased) queue=\(queue.rawValue)")
        
        if DownloadManager.shared.queueRunning { return }
        
        //some repos(eg:Chariz) only set the latest packages as cydia::commercial
        guard let mainPackage = self.package else {
            return
        }
        
        //local deb?
        guard let repo = package.sourceRepo, mainPackage.commercial, !self.hasPurchased, queue != .uninstallations else {
            return queuePackage(package, queue)
        }
        
        PaymentManager.shared.getPaymentProvider(for: repo) { error, provider in
            if let error = error {
                self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
                return
            }
            guard let provider = provider else {
                self.presentAlert(paymentError: .noPaymentProvider, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
                return
            }

            if !provider.isAuthenticated {
                return self.authenticate(provider: provider, package: package, completion: {
                    self.requestQueuePackage(package: package, queue: queue)
                })
            }
            
            self.updatePurchaseStatus(provider, package) { purchased in
                if purchased {
                    NSLog("SileoLog: updatePurchaseStatus add(package=\(package))")
                    self.queuePackage(package, queue)
                } else {
                    self.initatePurchase(provider: provider, package: package, queue: queue)
                }
            }
        }
    }
    
    private func updatePurchaseStatus(_ provider: PaymentProvider, _ package: Package, _ completion: ((Bool) -> Void)?) {
        provider.getPackageInfo(forIdentifier: package.package) { error, info in
            if let error = error {
                return self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
            }
            guard let info = info else {
                return self.presentAlert(paymentError: .invalidResponse, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
            }
            if !info.available {
                return self.presentAlert(paymentError: PaymentError(message: String(localizationKey: "Package_Unavailable")),
                                  title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
            }
            
            self.paymentInfo = info
            
            completion?(info.purchased)
            return
        }
    }
    
    private func initatePurchase(provider: PaymentProvider, package: Package, queue: DownloadManagerQueue) {
        provider.initiatePurchase(forPackageIdentifier: package.package) { error, status, actionURL in
            if let error = error {
                if error.shouldInvalidate {
                    self.authenticate(provider: provider, package: package, completion: {
                        self.requestQueuePackage(package: package, queue: queue)
                    })
                    return
                }
                return self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Initiate_Fail.Title", type: .error))
            }
            if status == .immediateSuccess {
                //it's necessary to check the purchase status again?
                //return return self.requestQueuePackage(package: package, queue: queue)
                
                self.updatePurchaseStatus(provider, package, nil) //update button info
                return self.queuePackage(package, queue)
            }
            else if status == .actionRequired {
                DispatchQueue.main.async {
                    PaymentAuthenticator.shared.handlePayment(actionURL: actionURL!, provider: provider, window: self.window) { error, success in
                        if let error = error {
                            let title = String(localizationKey: "Purchase_Complete_Fail.Title", type: .error)
                            return self.presentAlert(paymentError: error, title: title)
                        }
                        if success {
                            //it's necessary to check the purchase status again?
                            //return return self.requestQueuePackage(package: package, queue: queue)
                            
                            self.updatePurchaseStatus(provider, package, nil) //update button info
                            return self.queuePackage(package, queue)
                        }
                    }
                }
            }
        }
    }
    
    private func authenticate(provider: PaymentProvider, package: Package, completion:@escaping ()->Void) {
        DispatchQueue.main.async {
            PaymentAuthenticator.shared.authenticate(provider: provider, window: self.window) { error, success in
                if let error = error {
                    return self.presentAlert(paymentError: error, title: String(localizationKey: "Purchase_Auth_Complete_Fail.Title", type: .error))
                }
                if success {
                    return completion()
                }
            }
        }
    }
    
    private func presentAlert(paymentError: PaymentError?, title: String) {
        SileoAppDelegate.presentController(PaymentError.alert(for: paymentError, title: title))
    }
    
    private func hapticResponse() {
        if #available(iOS 13, *) {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}

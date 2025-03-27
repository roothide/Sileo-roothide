//
//  PackageViewController.swift
//  Sileo
//
//  Created by CoolStar on 8/31/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import SafariServices
import MessageUI
import Evander
import os.log

class PackageViewController: SileoViewController, PackageQueueButtonDataProvider,
    UIScrollViewDelegate, DepictionViewDelegate, MFMailComposeViewControllerDelegate, PackageActions {
    public var package: Package?
    public var depictionHeight = CGFloat(0)

    public var isPresentedModally = false

    private weak var weakNavController: UINavigationController?

    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentView: UIView!

    @IBOutlet private var packageName: UILabel!
    @IBOutlet private var packageAuthor: UILabel!

    @IBOutlet private var packageIconView: PackageIconView!

    @IBOutlet private var downloadButton: PackageQueueButton!
    private var navBarDownloadButton: PackageQueueButton?
    private var packageNavBarIconView: PackageIconView?
    private var shareButton: UIButton?

    private var navBarShareButtonItem: UIBarButtonItem?
    private var navBarDownloadButtonItem: UIBarButtonItem?

    private var depictionView: DepictionBaseView?
    private var depictionFooterView: DepictionBaseView?

    private var paymentProvider = ""
    private var price = ""
    private var purchased = false
    private var available = false
    private var headerURL: String?

    private var installedPackage: Package?

    @IBOutlet private var depictionHeaderView: UIView!
    @IBOutlet private var depictionBackgroundShadow: UIImageView!
    @IBOutlet private var depictionBackgroundView: UIImageView!
    @IBOutlet private var packageInfoView: UIStackView!

    @IBOutlet private var depictionHeaderImageViewHeight: NSLayoutConstraint!
    @IBOutlet private var contentViewHeight: NSLayoutConstraint!
    @IBOutlet private var contentViewWidth: NSLayoutConstraint!
//    @IBOutlet private var downloadButtonWidth: NSLayoutConstraint!

    private var allowNavbarUpdates = false
    private var currentNavBarOpacity = CGFloat(0)
    
    private func parseNativeDepiction(_ data: Data, host: String, failureCallback: (() -> Void)?) {
        guard let rawJSON = try? JSONSerialization.jsonObject(with: data, options: []),
              let rawDepict = rawJSON as? [String: Any]
        else {
            failureCallback?()
            return
        }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.parseNativeDepiction(data, host: host, failureCallback: failureCallback)
            }
            return
        }
        
        if let rawTintColor = rawDepict["tintColor"] as? String, let tintColor = UIColor(css: rawTintColor) {
            self.depictionFooterView?.tintColor = tintColor
            self.downloadButton.tintColor = tintColor
            self.downloadButton.updateStyle()
            self.navBarDownloadButton?.tintColor = tintColor
            self.navBarDownloadButton?.updateStyle()
        }
        
        let oldDepictView = self.depictionView
        guard let newDepictView = DepictionBaseView.view(dictionary: rawDepict, viewController: self, tintColor: nil, isActionable: false) else {
            return
        }
        
        oldDepictView?.delegate = nil
        newDepictView.delegate = self
        
        if let imageURL = rawDepict["headerImage"] as? String {
            if imageURL != headerURL {
                self.headerURL = imageURL
                EvanderNetworking.image(url: imageURL, condition: ({ [weak self] in self?.headerURL == imageURL}), imageView: depictionBackgroundView)
            }
        }
        
        newDepictView.alpha = 0.1
        self.depictionView = newDepictView
        self.contentView.addSubview(newDepictView)
        self.view.setNeedsLayout()
        
        FRUIView.animate(withDuration: 0.25, animations: {
            oldDepictView?.alpha = 0
            newDepictView.alpha = 1
        }, completion: { _ in
            oldDepictView?.removeFromSuperview()
            if let minVersion = rawDepict["minVersion"] as? String,
                minVersion.compare(StoreVersion) == .orderedDescending {
                self.versionTooLow()
            }
        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        weakNavController = self.navigationController
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        
        packageName.textColor = .sileoLabel
        let collapsed = splitViewController?.isCollapsed ?? false
        let navController = collapsed ? (splitViewController?.viewControllers[0] as? UINavigationController) : self.navigationController
        navController?.setNavigationBarHidden(true, animated: true)

        self.navigationItem.largeTitleDisplayMode = .never
        scrollView.delegate = self
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageViewController.reloadData),
                                               name: PackageListManager.reloadNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(PackageViewController.reloadData),
                                               name: PackageListManager.installChange,
                                               object: nil)

        packageIconView.layer.cornerRadius = 15

        self.extendedLayoutIncludesOpaqueBars = true
        self.edgesForExtendedLayout = [.top, .bottom]

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: self.tabBarController?.tabBar.bounds.height ?? 0, right: 0)

        allowNavbarUpdates = true
        depictionHeaderImageViewHeight.constant = 200
        self.navigationController?.navigationBar._backgroundOpacity = 0
        self.navigationController?.navigationBar.tintColor = .white
        self.statusBarStyle = .lightContent
        
        self.navigationController?.navigationBar.isTranslucent = true
        
        downloadButton.viewControllerForPresentation = self
        
        let navBarDownloadButton = PackageQueueButton()
        navBarDownloadButton.viewControllerForPresentation = self
        self.navBarDownloadButton = navBarDownloadButton

        let shareButton = UIButton(type: .custom)
        shareButton.setImage(UIImage(named: "More"), for: .normal)
        shareButton.addTarget(self, action: #selector(PackageViewController.sharePackage), for: .touchUpInside)
        shareButton.accessibilityIgnoresInvertColors = true
        self.shareButton = shareButton

        navBarDownloadButton.alpha = 0

        navBarDownloadButtonItem = UIBarButtonItem(customView: navBarDownloadButton)
        let navBarShareButtonItem = UIBarButtonItem(customView: shareButton)
        self.navBarShareButtonItem = navBarShareButtonItem

        self.navigationItem.rightBarButtonItems = [navBarShareButtonItem]

        let packageNavBarIconViewController = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 50, height: 32)))

        let packageNavBarIconView = PackageIconView(frame: CGRect(origin: .zero, size: CGSize(width: 32, height: 32)))
        packageNavBarIconView.center = packageNavBarIconViewController.center
        packageNavBarIconView.alpha = 0
        self.packageNavBarIconView = packageNavBarIconView

        packageNavBarIconViewController.addSubview(packageNavBarIconView)
        self.navigationItem.titleView = packageNavBarIconViewController

        if self.isPresentedModally {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localizationKey: "Done"),
                                                                    style: .done,
                                                                    target: self,
                                                                    action: #selector(PackageViewController.dismissImmediately))
            
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(PackageViewController.dismissImmediately),
                                                   name: PackageQueueButton.actionPerformedNotification,
                                                   object: nil)
            
            downloadButton.NoAnimation = true
            navBarDownloadButton.NoAnimation = true
        }

        self.reloadData()
        
        if let package=self.package {
            CanisterResolver.shared.ingest(packages: [package])
        }
    }

    @objc func updateSileoColors() {
        packageName.textColor = .sileoLabel
    }
    
    private var savedProvisional: Package?
    
    @objc func reloadData() {
        NSLog("SileoLog: PackageViewController.reloadData")
        guard Thread.current.isMainThread else {
            DispatchQueue.main.async {
                self.reloadData()
            }
            return
        }
        
        defer {
            self.view.layoutIfNeeded()
        }
        
        depictionView?.removeFromSuperview()
        depictionView = nil
        
        if let package=package, let source=package.source, package.isProvisional ?? false {
            if let repo = RepoManager.shared.repo(with: source.uri, suite: source.suite, components: source.component?.components(separatedBy: .whitespaces) )
            {
                if let newPackage = PackageListManager.shared.newestPackage(identifier: package.package, repoContext: repo) {
                    self.savedProvisional = self.package
                    self.package = newPackage
                }
            }
        }
        
        if let package=package, package.fromStatusFile {
            if let newInstalled = PackageListManager.shared.installedPackage(identifier: package.package) {
                self.package = newInstalled
            }
        }

        guard var package = self.package else {
            return
        }
        
        if let backup = self.savedProvisional, package.sourceRepo==nil {
            package = backup
            self.package = backup
            self.savedProvisional = nil
        }

        let installedPackage = PackageListManager.shared.installedPackage(identifier: package.package)
        self.installedPackage = installedPackage

        packageName.text = package.name
        packageAuthor.text = package.author?.name ?? ""

        downloadButton.package = package
        navBarDownloadButton?.package = package
        
        self.updatePaymentInfo()
        
        if let imageURL = package.rawControl["header"] {
            if imageURL != headerURL {
                self.headerURL = imageURL
                EvanderNetworking.image(url: imageURL, size: CGSize(width: depictionBackgroundView.frame.width, height: 200), condition: ({ [weak self] in self?.headerURL == imageURL }), imageView: depictionBackgroundView)
            }
        }
        
        if package.hasIcon(),
            let rawIcon = package.icon {
            EvanderNetworking.image(url: rawIcon, size: packageIconView.frame.size, condition: ({ [weak self] in self?.package?.icon == rawIcon}), imageViews: [packageIconView, packageNavBarIconView], fallback: package.defaultIcon)
        } else {
            packageNavBarIconView?.image = package.defaultIcon
            packageIconView.image = package.defaultIcon
        }

        var rawDescription: [[String: Any]] = [
            [
                "class": "DepictionMarkdownView",
                "markdown": package.description ?? String(localizationKey: "Package_No_Description_Available"),
                "useSpacing": true
            ]
        ]

        if package.sileoDepiction == nil,
            let legacyDepiction = package.legacyDepiction {
            rawDescription.append([
                "class": "DepictionTableButtonView",
                "title": String(localizationKey: "View_Depiction"),
                "action": legacyDepiction.absoluteString
            ] as [String: Any])
        }

        let rawDepiction = package.sourceRepo==nil ? [
            "class": "DepictionStackView",
            "views": [
                [
                    "class": "DepictionHeaderView",
                    "title": String(localizationKey: "Package_Details_Tab"),
                    "useBoldText" : true,
//                    "fontSize" : 17
                ],
                ["class": "DepictionSeparatorView"],
            ] + rawDescription
        ] : [
            "class": "DepictionTabView",
            "tabs": [
                [
                    "tabname": String(localizationKey: "Package_Details_Tab"),
                    "class": "DepictionStackView",
                    "views": rawDescription
                ], [
                    "tabname": String(localizationKey: "Package_Changelog_Tab"),
                    "class": "DepictionStackView",
                    "views": [[
                        "class": "DepictionMarkdownView",
                        "markdown": String(localizationKey: "Package_Changelogs_Unavailable"),
                        "useSpacing": true
                    ]]
                ]
            ]
        ] as [String: Any]

        if let depictionView = DepictionBaseView.view(dictionary: rawDepiction, viewController: self, tintColor: nil, isActionable: false) {
            depictionView.delegate = self
            contentView.addSubview(depictionView)
            self.depictionView = depictionView
        }

        if !package.fromStatusFile,
            let depiction = package.sileoDepiction {
            let urlRequest = URLManager.urlRequest(depiction)
            EvanderNetworking.request(request: urlRequest, type: Data.self) { [weak self] success, _, _, data in
                guard success,
                      let data = data,
                      let `self` = self else { return }
                self.parseNativeDepiction(data, host: depiction.host ?? "", failureCallback: nil)
            }
        }

        var footerViews = [[String: Any]]()
        if let installedPackage = installedPackage {
            footerViews.append(contentsOf: [
                [
                    "class": "DepictionSeparatorView"
                ],
                [
                    "class": "DepictionHeaderView",
                    "title": String(localizationKey: "Installed_Package_Header")
                ],
                [
                    "class": "DepictionTableTextView",
                    "title": String(localizationKey: "Version"),
                    "text": installedPackage.version
                ],
                [
                    "class": "DepictionTableButtonView",
                    "title": String(localizationKey: "Show_Package_Contents_Button"),
                    "action": "showInstalledContents"
                ],
                [
                    "class": "DepictionSeparatorView"
                ]
            ])
        }
        
        if let repo = package.sourceRepo {
            footerViews.insert([
                "class": "DepictionSeparatorView"
            ], at: 0)
            footerViews.insert([
                "class": "DepictionHeaderView",
                "title": String(localizationKey: "Repo")
            ], at: 1)
            footerViews.insert([
                "class": "DepictionTableButtonView",
                "title": RepoManager.shared.getUniqueName(repo: repo),
                "action": "showRepoContext",
                "context": repo as Any,
                "_repo": repo.url?.absoluteString as Any
            ], at: 2)
        }
        else if package.fromStatusFile {
            
            var repoPackages: [Package] = []
            for repo in RepoManager.shared.repoList {
                if let repoPackage = repo.newestPackage(identifier: package.package, ignoreArch: true) {
                    repoPackages.append(repoPackage)
                }
            }
            
            repoPackages = PackageListManager.shared.sortPackages(packages: repoPackages, search: nil)
            
            if repoPackages.count > 0
            {
                footerViews.insert([
                    "class": "DepictionSeparatorView"
                ], at: 0)
                footerViews.insert([
                    "class": "DepictionHeaderView",
                    "title": String(localizationKey: "Repo")
                ], at: 1)
                
                var viewIndex = 2
                for package in repoPackages {
                    guard let repo = package.sourceRepo else {
                        continue
                    }
                    footerViews.insert([
                        "class": "DepictionTableTextButtonView",
                        "title": repo.displayName,
                        "text": package.version,
                        "action": "showPackage",
                        "context": package as Any,
                    ], at: viewIndex++)
                }
            }
        }
        else if let source=package.source, package.isProvisional ?? false {
            var url: String

            if source.suite == "./" {
                url = source.uri.absoluteString
            } else if let component = source.component {
                url = source.uri.appendingPathComponent("dists").appendingPathComponent(source.suite).appendingPathComponent(component).absoluteString
            } else {
                url = "Invalid"
            }
                
            footerViews.insert([
                "class": "DepictionSeparatorView"
            ], at: 0)
            footerViews.insert([
                "class": "DepictionHeaderView",
                "title": String(localizationKey: "Repo")
            ], at: 1)
            footerViews.insert([
                "class": "DepictionSubheaderView",
                "useBoldText": true,
                "title": url
            ], at: 2)
        }
        
        footerViews.append([
            "class": "DepictionSubheaderView",
            "alignment": 1,
            "title": "\(package.package) (\(package.version))"
        ])
        
        let footerDict = [
            "class": "DepictionStackView",
            "views": footerViews
        ] as [String: Any]

        
        depictionFooterView?.removeFromSuperview()
        depictionFooterView = nil
        
        if let depictionFooterView = DepictionBaseView.view(dictionary: footerDict, viewController: self, tintColor: nil, isActionable: false) {
            depictionFooterView.delegate = self
            self.depictionFooterView = depictionFooterView
            contentView.addSubview(depictionFooterView)
        }
    }

    func versionTooLow() {
        let alertController = UIAlertController(title: String(localizationKey: "Sileo_Update_Required.Title", type: .error),
                                                message: String(localizationKey: "Featured_Requires_Sileo_Update", type: .error),
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        }))
        self.present(alertController, animated: true, completion: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.statusBarStyle = .default
        
        self.navigationController?.navigationBar._backgroundOpacity = currentNavBarOpacity
        self.navigationController?.navigationBar.tintColor = .white
        allowNavbarUpdates = true
        self.scrollViewDidScroll(self.scrollView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        let collapsed = splitViewController?.isCollapsed ?? false
        let navController = collapsed ? (splitViewController?.viewControllers[0] as? UINavigationController) : weakNavController
        
        allowNavbarUpdates = false
        currentNavBarOpacity = navController?.navigationBar._backgroundOpacity ?? 1
        
        FRUIView.animate(withDuration: 0.8) {
            navController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
            navController?.navigationBar._backgroundOpacity = 1
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // do header view scaling magic
        let headerBounds = depictionHeaderView.bounds
        var aspectRatio = headerBounds.width / headerBounds.height
        if headerBounds.height == 0 {
            aspectRatio = 0
        }

        var offset = scrollView.contentOffset.y
        if offset > 0 {
            offset = 0
        }

        var headerBackgroundFrame = CGRect.zero
        headerBackgroundFrame.size.height = headerBounds.height - offset
        headerBackgroundFrame.size.width = headerBackgroundFrame.height * aspectRatio
        headerBackgroundFrame.origin.x = (headerBounds.width - headerBackgroundFrame.width)/2
        headerBackgroundFrame.origin.y = headerBounds.height - headerBackgroundFrame.height

        depictionBackgroundView.frame = headerBackgroundFrame
        depictionBackgroundShadow.frame = headerBackgroundFrame

        // doing the magic on the nav bar "GET" button and package icon
        let downloadButtonPos = downloadButton.convert(downloadButton.bounds, to: scrollView)
        let container = CGRect(origin: CGPoint(x: scrollView.contentOffset.x,
                                               y: scrollView.contentOffset.y + 106 - UIApplication.shared.statusBarFrame.height),
                               size: scrollView.frame.size)
        // TLDR: magic starts when scrolling out the lower half of the button so we don't have duplicated button too early
        var navBarAlphaOffset = scrollView.contentOffset.y * 1.75 / depictionHeaderImageViewHeight.constant
        if depictionHeaderImageViewHeight.constant == 0 {
            navBarAlphaOffset = 0
        }

        if navBarAlphaOffset > 1 {
            navBarAlphaOffset = 1
        } else if navBarAlphaOffset < 0 {
            navBarAlphaOffset = 0
        }

        FRUIView.animate(withDuration: 0.3) {
            self.shareButton?.alpha = 1 - navBarAlphaOffset

            if (self.shareButton?.alpha ?? 0) > 0 {
                self.packageNavBarIconView?.alpha = 0
            } else {
                self.packageNavBarIconView?.alpha = downloadButtonPos.intersects(container) ? 0 : 1
            }
            self.navBarDownloadButton?.customAlpha = self.packageNavBarIconView?.alpha ?? 0

            if let navBarDownloadButtonItem = self.navBarDownloadButtonItem,
                let navBarShareButtonItem = self.navBarShareButtonItem {
                if (self.shareButton?.alpha ?? 0) > 0 {
                    self.navigationItem.rightBarButtonItems = [navBarShareButtonItem]
                } else {
                    self.navigationItem.rightBarButtonItems = [navBarDownloadButtonItem]
                }
            }
        }

        scrollView.scrollIndicatorInsets.top = max(headerBounds.maxY - scrollView.contentOffset.y, self.view.safeAreaInsets.top)

        guard allowNavbarUpdates else {
            return
        }
        
        let collapsed = splitViewController?.isCollapsed ?? false
        let navController = collapsed ? (splitViewController?.viewControllers[0] as? UINavigationController) : self.navigationController
        navController?.setNavigationBarHidden(false, animated: true)
        if navBarAlphaOffset < 1 {
            var tintColor = UINavigationBar.appearance().tintColor
            if let color = self.depictionView?.tintColor {
                tintColor = color
            }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            tintColor?.getRed(&red, green: &green, blue: &blue, alpha: nil)

            if UIAccessibility.isInvertColorsEnabled {
                red -= red * (1.0 - navBarAlphaOffset)
                green -= green * (1.0 - navBarAlphaOffset)
                blue -= blue * (1.0 - navBarAlphaOffset)
            } else {
                red += (1.0 - red) * (1.0 - navBarAlphaOffset)
                green += (1.0 - green) * (1.0 - navBarAlphaOffset)
                blue += (1.0 - blue) * (1.0 - navBarAlphaOffset)
            }
            tintColor = UIColor(red: red, green: green, blue: blue, alpha: 1)

            navController?.navigationBar.tintColor = tintColor
            navController?.navigationBar._backgroundOpacity = navBarAlphaOffset
            if navBarAlphaOffset < 0.75 {
                self.statusBarStyle = .lightContent
            } else {
                self.statusBarStyle = .default
            }
        } else {
            navController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
            if let tintColor = self.depictionView?.tintColor {
                navController?.navigationBar.tintColor = tintColor
            }
            navController?.navigationBar._backgroundOpacity = 1
            self.statusBarStyle = .default
        }
        self.setNeedsStatusBarAppearanceUpdate()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // for those wondering about the magic numbers and what's going on here:
        // This is the spring effect on scrolling (aka step to start or step to after header
        // 113 = header imageView height - nav bar height and 56 is simply for setitng the step boundary, aka halfway
        // if you don't like this, we can implement the variables from above, instead, but imo it's a waste of time
        let scrollViewOffset = scrollView.contentOffset.y + UIApplication.shared.statusBarFrame.height
        
        if scrollViewOffset < 66 {
            scrollView.setContentOffset(.zero, animated: true)
        } else if scrollViewOffset > 66 && scrollViewOffset < 133 {
            scrollView.setContentOffset(CGPoint(x: 0, y: 156 - UIApplication.shared.statusBarFrame.height), animated: true)
        }
    }

    func subviewHeightChanged() {
        NSLog("SileoLog: PackageViewController.subviewHeightChanged")
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        NSLog("SileoLog: PackageViewController.viewDidLayoutSubviews")
//        Thread.callStackSymbols.forEach{NSLog("SileoLog: viewDidLayoutSubviews callstack=\($0)")}
        
        super.viewDidLayoutSubviews()

        depictionHeight = depictionView?.depictionHeight(width: self.view.bounds.width) ?? 0

        let headerHeight = packageInfoView.frame.maxY

        depictionView?.frame = CGRect(x: 0, y: headerHeight, width: self.view.bounds.width, height: depictionHeight)

        let footerHeight = depictionFooterView?.depictionHeight(width: self.view.bounds.width) ?? 0
        depictionFooterView?.frame = CGRect(x: 0, y: headerHeight + depictionHeight, width: self.view.bounds.width, height: footerHeight)

        contentView.frame = CGRect(origin: .zero, size: CGSize(width: self.view.bounds.width, height: headerHeight + depictionHeight + footerHeight))
        scrollView.contentSize = CGSize(width: self.view.bounds.width, height: headerHeight + depictionHeight + footerHeight)

        contentViewWidth.constant = scrollView.bounds.width
        contentViewHeight.constant = headerHeight + depictionHeight + footerHeight

        self.view.updateConstraintsIfNeeded()

        scrollView.contentSize = CGSize(width: scrollView.contentSize.width, height: contentViewHeight.constant)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            self.scrollViewDidScroll(self.scrollView)
        }
    }

    @objc func sharePackage(_ sender: Any?) {
        guard let package = self.package,
            let shareButton = self.shareButton else {
            return
        }
        
        let sharePopup = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let shareAction = UIAlertAction(title: String(localizationKey: "Package_Share_Action"), style: .default) { _ in
            var packageString = "\(package.name ?? package.package) - \(URLManager.url(package: package.package))"
            if let repo = package.sourceRepo {
                packageString += " - from \(repo.url?.absoluteString ?? repo.rawURL)"
            }
            let activityViewController = UIActivityViewController(activityItems: [packageString], applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = shareButton
            self.present(activityViewController, animated: true, completion: nil)
        }
        sharePopup.addAction(shareAction)
        
        if let author = package.author {
            if let name = author.name {
                 let moreByDeveloper = UIAlertAction(title: String(localizationKey: "Package_Developer_Find_Action"
                 ), style: .default) { _ in
                     let packagesListController = PackageListViewController(nibName: "PackageListViewController", bundle: nil)
                     packagesListController.packagesLoadIdentifier = "author:\(name)"
                     packagesListController.title = String(format: String(localizationKey: "Packages_By_Author"),
                                                           author.name ?? "")
                     self.navigationController?.pushViewController(packagesListController, animated: true)
                 }
                 sharePopup.addAction(moreByDeveloper)
             
            }
            
            if let email = author.email {
                let packageSupport = UIAlertAction(title: String(localizationKey: "Package_Support_Action"), style: .default) { _ in
                    func unavailable() {
                        let alertController = UIAlertController(title: String(localizationKey: "Email_Unavailable.Title", type: .error),
                                                                message: String(localizationKey: "Email_Unavailable.Body", type: .error),
                                                                preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .cancel, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    }
                    guard let subject = "Sileo/APT(M): \(package.name ?? package.package)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                          let email = email.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                          let url = URL(string: "mailto:\(email)?subject=\(subject)") else {
                        return unavailable()
                    }
                    UIApplication.shared.open(url) { success in
                        if !success {
                            unavailable()
                        }
                    }
                }
                sharePopup.addAction(packageSupport)
            }
        }
        
        if let installedPackage = installedPackage, let package = self.package {
            let ignoreUpdatesText = installedPackage.wantInfo == .hold ?
                String(localizationKey: "Package_Hold_Disable_Action") : String(localizationKey: "Package_Hold_Enable_Action")
            let ignoreUpdates = UIAlertAction(title: ignoreUpdatesText, style: .default) { _ in
                do {
                    if installedPackage.wantInfo == .hold {
#if !targetEnvironment(simulator) && !TARGET_SIMULATOR
                        try DpkgWrapper.ignoreUpdates(false, package: package.package)
                        installedPackage.wantInfo = .install
#endif
                    } else {
#if !targetEnvironment(simulator) && !TARGET_SIMULATOR
                        try DpkgWrapper.ignoreUpdates(true, package: package.package)
                        installedPackage.wantInfo = .hold
#endif
                    }
                    NotificationCenter.default.post(Notification(name: PackageListManager.prefsNotification))
                } catch {
                    sharePopup.dismiss(animated: true) {
                        let alertController = UIAlertController(title: String(localizationKey: "Unknown", type: .error), message: "\(error)", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .cancel, handler: { _ in
                            self.dismiss(animated: true, completion: nil)
                        }))
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            }
            sharePopup.addAction(ignoreUpdates)
        }
        
        let wishListText = WishListManager.shared.isPackageInWishList(package.package) ?
            String(localizationKey: "Package_Wishlist_Remove") : String(localizationKey: "Package_Wishlist_Add")
        let wishlist = UIAlertAction(title: wishListText, style: .default) { _ in
            if WishListManager.shared.isPackageInWishList(package.package) {
                WishListManager.shared.removePackageFromWishList(package.package)
            } else {
                _ = WishListManager.shared.addPackageToWishList(package.package)
            }
        }
        sharePopup.addAction(wishlist)
        
        let cancelAction = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: nil)
        sharePopup.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            sharePopup.popoverPresentationController?.sourceView = shareButton
        }
        if let tintColor = depictionView?.tintColor {
            sharePopup.view.tintColor = tintColor
        }
        self.present(sharePopup, animated: true)
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        // Check the result or perform other tasks.

        // Dismiss the mail compose view controller.
        self.dismiss(animated: true, completion: nil)
    }

    @objc func dismissImmediately() {
        // Dismiss this view controller.
        self.dismiss(animated: true, completion: nil)
    }
    
    private func updatePaymentInfo()
    {
        guard let package = self.package, package.commercial, let repo = package.sourceRepo else {
            DispatchQueue.main.async {
                self.downloadButton.paymentInfo = nil
                self.navBarDownloadButton?.paymentInfo = nil
            }
            return
        }
        
        PaymentManager.shared.getPaymentProvider(for: repo) { error, provider in
            guard error == nil, let provider = provider else {
                return
            }
            
// we can always request price for packages even if the repo is not logged in
//                guard provider.isAuthenticated else {
//                    return //we have to re-verify its payment status if the repo is not logged in
//                }

            provider.getPackageInfo(forIdentifier: package.package) { error, info in
                guard error == nil, let info=info, info.available else { return }
                
                self.downloadButton.paymentInfo = info
                self.navBarDownloadButton?.paymentInfo = info
            }
        }
    }
    
    override var previewActionItems: [UIPreviewActionItem] {
        downloadButton.actionItems().map({ $0.previewAction() })
    }
    
    @available (iOS 13.0, *)
    func actions() -> [UIAction] {
        _ = self.view
        return downloadButton.actionItems().map({ $0.action() })
    }
}

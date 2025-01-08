//
//  SourcesTableViewCell.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

class SourcesTableViewCell: BaseSubtitleTableViewCell {
    
    static var repoImageUpdate = Notification.Name("Sileo.RepoImageUpdate")
    
    public weak var repo: Repo? = nil {
        didSet {
            if let repo = repo {
                self.title = repo.displayName
                self.subtitle = repo.displayURL
                self.progress = repo.totalProgress
                self.image(repo)
                installedLabel.text = "\(repo.installed?.count ?? 0)"
            } else {
                self.title = String(localizationKey: "All_Packages.Title")
                self.subtitle = String(localizationKey: "All_Packages.Cell_Subtitle")
                self.icon = UIImage(named: "All Packages")
                self.progress = 0
                installedLabel.text = "\(PackageListManager.shared.installedPackages.count)"
            }
            
//            textLabel?.semanticContentAttribute = .forceLeftToRight
//            detailTextLabel?.semanticContentAttribute = .forceLeftToRight
        }
    }
    public var installedLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
//        accessoryView = UIImageView(image: UIImage(named: "Chevron"))
        self.accessoryType = .disclosureIndicator
        self.detailTextLabel?.adjustsFontSizeToFitWidth = true
        
        contentView.addSubview(installedLabel)
        installedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.trailingAnchor.constraint(equalTo: installedLabel.trailingAnchor, constant: 7.5).isActive = true
        installedLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        installedLabel.font = UIFont.systemFont(ofSize: 12)
        installedLabel.textColor = UIColor(red: 145.0/255.0, green: 155.0/255.0, blue: 162.0/255.0, alpha: 1)
        
        installedLabel.addObserver(self, forKeyPath: "bounds", options: [.new, .old], context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

//        NSLog("SileoLog: observeValue \(keyPath) \(change?[.newKey]) \(change?[.oldKey])")
        if keyPath == "bounds", let newBounds = change?[.newKey] as? CGRect {
            updateContentLayout(installedSize: newBounds.size)
        }
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        
        updateContentLayout(installedSize: installedLabel.frame.size)
    }
    
    private func updateContentLayout(installedSize: CGSize)
    {
        guard var textLabelFrame = self.textLabel?.frame,
            var detailTextLabelFrame = self.detailTextLabel?.frame else {
                return
        }
        
        let fix = installedLabel.bounds.size.width + 7.5 + 5
//        NSLog("SileoLog: updateContentLayout \(fix) \(installedSize)")
        if UIView.userInterfaceLayoutDirection(for: self.semanticContentAttribute) == .leftToRight {
            textLabelFrame.size.width = contentView.frame.size.width - textLabelFrame.origin.x  - fix
            detailTextLabelFrame.size.width = contentView.frame.size.width - detailTextLabelFrame.origin.x  - fix
        } else {
            let fix2 = contentView.frame.size.width - (textLabelFrame.origin.x+textLabelFrame.size.width)
            let textLableWidthMax = contentView.frame.size.width - fix2 - fix
            if textLabelFrame.size.width > textLableWidthMax {
                textLabelFrame.size.width = textLableWidthMax
                textLabelFrame.origin.x = fix
            }
            
            let fix3 = contentView.frame.size.width - (detailTextLabelFrame.origin.x+detailTextLabelFrame.size.width)
            let detailTextLableWidthMax = contentView.frame.size.width - fix3 - fix
            if detailTextLabelFrame.size.width > detailTextLableWidthMax {
                detailTextLabelFrame.size.width = detailTextLableWidthMax
                detailTextLabelFrame.origin.x = fix
            }
        }

        self.textLabel?.frame = textLabelFrame
        self.detailTextLabel?.frame = detailTextLabelFrame
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.repo = nil
    }

    public func image(_ repo: Repo) {
        // Quite frankly the backend here sucks ass, so if you open the sources page too quick after launching the image will not be set
        // This will pull it from local cache in the event that we're too quick. If doesn't exist in Cache, show the default icon
        if repo.url?.host == "apt.thebigboss.org" {
            let url = StoreURL("deprecatedicons/BigBoss@\(Int(UIScreen.main.scale))x.png")!
            let cache = EvanderNetworking.imageCache(url, scale: UIScreen.main.scale)
            if let image = cache.1 {
                self.icon = image
                return
            }
        }
        if let icon = repo.repoIcon {
            self.icon = icon
            return
        }
        let scale = Int(UIScreen.main.scale)
        for i in (1...scale).reversed() {
            let filename = i == 1 ? CommandPath.RepoIcon : "\(CommandPath.RepoIcon)@\(i)x"
            if let iconURL = URL(string: repo.repoURL)?
                .appendingPathComponent(filename)
                .appendingPathExtension("png") {
                let cache = EvanderNetworking.imageCache(iconURL, scale: CGFloat(i))
                if let image = cache.1 {
                    self.icon = image
                    return
                }
            }
        }
        self.icon = UIImage(named: "Repo Icon")
    }
}

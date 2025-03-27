//
//  DownloadsTableViewCell.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

class DownloadsTableViewCell: BaseSubtitleTableViewCell {
    public var package: Package? {
        didSet {
            self.title = package?.name
            if let url = package?.icon {
                self.icon = EvanderNetworking.image(url: url, size: iconView.frame.size) { [weak self] image in
                    if let strong = self,
                       url == strong.package?.icon {
                        DispatchQueue.main.async {
                            strong.icon = image
                        }
                    }
                } ?? package?.defaultIcon
            } else {
                self.icon = package?.defaultIcon
            }
        }
    }
    
    public var action: DownloadsTableViewController.Action? {
        didSet {
            NSLog("SileoLog: didSet action \(action?.package) \(action?.progress) \(action?.status)")
            action?.cell = self
        }
    }
    
    public var download: Download? = nil {
        didSet {
            retryButton.isHidden = true
        }
    }
    
    public var errorDescription: String? = nil {
        didSet {
            let errored = errorDescription != nil
            self.textLabel?.textColor = errored ? UIColor(hue: 0.0, saturation: 0.8, brightness: 0.9, alpha: 0.8) : .sileoLabel
            self.detailTextLabel?.textColor = errored ? UIColor(hue: 0.0, saturation: 1.0, brightness: 1.0, alpha: 1.0) : UIColor(red: 172.0/255.0, green: 184.0/255.0, blue: 193.0/255.0, alpha: 1)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        icon = nil
        title = nil
        subtitle = nil
        progress = 0
        package = nil
        download = nil
        action = nil
        action?.cell = nil
        errorDescription = nil
    }
    
    public func updateStatus() {
        NSLog("SileoLog: updateStatus \(package?.package) \(package?.sourceRepo?.repoName) download=\(download),\(download?.progress) action=\(action) err=\(errorDescription) oldsubtitle=\(self.subtitle)")

        if let err = errorDescription {
            self.progress = 0
            self.subtitle = String(localizationKey: err)
        } else if let action = self.action {
            var progress = action.progress
            progress = (progress / 1.0) * 0.3
            self.progress = progress + 0.7
            if let status = action.status {
                self.subtitle = status
            } else {
                self.subtitle = String(localizationKey: "Ready_Status")
            }
        } else if let download = download {
            self.progress = (download.progress / 1.0) * 0.7
            if download.progress == 1.0 && download.failureReason == nil {
                self.subtitle = String(localizationKey: "Ready_Status")
            } else if let message = download.message {
                self.subtitle = message
            } else if let failureReason = download.failureReason,
                !failureReason.isEmpty {
                retryButton.isHidden = false
                self.subtitle = String(format: String(localizationKey: "Error_Indicator", type: .error), failureReason)
            } else if download.started {
                if download.totalBytesWritten > 0 {
                    self.subtitle = String(format: String(localizationKey: "Download_Progress"),
                                           ByteCountFormatter.string(fromByteCount: Int64(download.totalBytesWritten), countStyle: .file),
                                           ByteCountFormatter.string(fromByteCount: Int64(download.totalBytesExpectedToWrite), countStyle: .file))
                } else {
                    self.subtitle = String(localizationKey: "Download_Starting")
                }
            } else {
                if let repoName = package?.sourceRepo?.repoName {
                    self.subtitle = "\(String(localizationKey: "Queued_Package_Status")) • \(repoName)"
                } else {
                    self.subtitle = String(localizationKey: "Queued_Package_Status")
                }
            }
        } else {
            self.progress = 0
            if let repoName = package?.sourceRepo?.repoName {
                self.subtitle = "\(String(localizationKey: "Queued_Package_Status")) • \(repoName)"
            } else {
                self.subtitle = String(localizationKey: "Queued_Package_Status")
            }
        }
    }
    
    public let retryButton = UIButton()
    
    @objc public func retryDownload() {
        
        self.download = nil
        self.updateStatus()
        
        DownloadManager.shared.retryDownload(package: self.package!.package)
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        
        self.selectionStyle = .none
        self.contentView.addSubview(retryButton)
        self.detailTextLabel?.adjustsFontSizeToFitWidth = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.heightAnchor.constraint(equalToConstant: 17.5).isActive = true
        retryButton.widthAnchor.constraint(equalToConstant: 17.5).isActive = true
        retryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        contentView.trailingAnchor.constraint(equalTo: retryButton.trailingAnchor, constant: 15).isActive = true
        
        retryButton.setImage(UIImage(named: "Refresh")?.withRenderingMode(.alwaysTemplate), for: .normal)
        retryButton.tintColor = .tintColor
        retryButton.addTarget(self, action: #selector(retryDownload), for: .touchUpInside)
        retryButton.isHidden = true
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

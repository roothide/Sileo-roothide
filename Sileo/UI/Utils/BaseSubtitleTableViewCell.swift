//
//  BaseSubtitleTableViewCell.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit
import Evander

open class BaseSubtitleTableViewCell: UITableViewCell {
    let iconView: PackageIconView
    let progressView: SourceProgressIndicatorView
    var iconURL: URL?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        iconView = PackageIconView(frame: CGRect(x: 16, y: 8, width: 40, height: 40))
        progressView = SourceProgressIndicatorView(frame: .zero)
    
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        self.contentView.addSubview(iconView)
        progressView.tintColor = SileoThemeManager.shared.tintColor
        self.contentView.insertSubview(progressView, at: 0)
        
        self.textLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        
        self.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        self.detailTextLabel?.textColor = UIColor(red: 145.0/255.0, green: 155.0/255.0, blue: 162.0/255.0, alpha: 1)
        
        self.backgroundColor = .clear
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        self.textLabel?.textColor = .sileoLabel
        self.selectedBackgroundView = SileoSelectionView(frame: .zero)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateSileoColors() {
        self.textLabel?.textColor = .sileoLabel
        progressView.tintColor = SileoThemeManager.shared.tintColor
    }
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        
        guard var textLabelFrame = self.textLabel?.frame,
            var detailTextLabelFrame = self.detailTextLabel?.frame else {
                return
        }
        let progressX = CGFloat(16)
        textLabelFrame.origin.y = 9
        detailTextLabelFrame.origin.y = 30
        
        let progressViewPadding = 3.0
        let contentOffset = self.convert(contentView.frame.origin, to: self)
        if UIView.userInterfaceLayoutDirection(for: self.semanticContentAttribute) == .leftToRight {
            if icon != nil {
                textLabelFrame.origin.x = 72
                detailTextLabelFrame.origin.x = 72
            } else {
                textLabelFrame.origin.x = 16
                detailTextLabelFrame.origin.x = 16
            }
            textLabelFrame.size.width = contentView.frame.size.width - textLabelFrame.origin.x
            detailTextLabelFrame.size.width = contentView.frame.size.width - detailTextLabelFrame.origin.x
            
            progressView.frame = CGRect(x: progressX, y: self.contentView.bounds.height - 2, width: self.bounds.width - contentOffset.x - progressX - progressViewPadding, height: 2)
            
        } else {
            if icon != nil {
                iconView.frame.origin.x = self.contentView.frame.size.width - 16 - iconView.frame.size.width
                
                textLabelFrame.origin.x = self.contentView.frame.size.width - textLabelFrame.size.width - 72
                detailTextLabelFrame.origin.x = self.contentView.frame.size.width - detailTextLabelFrame.size.width - 72
            } else {
                textLabelFrame.origin.x = self.contentView.frame.size.width - textLabelFrame.size.width - 16
                detailTextLabelFrame.origin.x = self.contentView.frame.size.width - detailTextLabelFrame.size.width - 16
            }
            if textLabelFrame.origin.x < 0 {
                textLabelFrame.size.width -= -textLabelFrame.origin.x
                textLabelFrame.origin.x = 0
            }
            if detailTextLabelFrame.origin.x < 0 {
                detailTextLabelFrame.size.width -= -detailTextLabelFrame.origin.x
                detailTextLabelFrame.origin.x = 0
            }
            
            let fix = self.frame.size.width - (contentOffset.x + self.contentView.frame.size.width)
            progressView.frame = CGRect(x: -contentOffset.x + progressViewPadding, y: self.contentView.bounds.height - 2, width: self.bounds.width - fix - progressX - progressViewPadding, height: 2)
        }
        
        self.textLabel?.frame = textLabelFrame
        self.detailTextLabel?.frame = detailTextLabelFrame
    }
    
    public var title: String? = nil {
        didSet {
            self.textLabel?.text = title
        }
    }
    
    public var subtitle: String? = nil {
        didSet {
            self.detailTextLabel?.text = subtitle
        }
    }
    
    public var icon: UIImage? = nil {
        didSet {
            iconView.image = icon
            iconView.isHidden = (icon == nil)
        }
    }
    
    func loadIcon(url: URL?, placeholderIcon: UIImage?) {
        iconURL = nil
        
        guard let url = url else {
            return
        }
        self.icon = EvanderNetworking.image(url: url, size: iconView.frame.size) { [weak self] image in
            guard let self = self,
                  url == self.iconURL else { return }
            DispatchQueue.main.async {
                self.icon = image
            }
        } ?? placeholderIcon
    }
    
    public var progress: CGFloat = 0 {
        didSet {
//            NSLog("SileoLog: progress=\(self.progress) \((self as? SourcesTableViewCell)?.repo?.url) \(self)")
//            Thread.callStackSymbols.forEach{NSLog("SileoLog: callstack=\($0)")}
            FRUIView.animate(withDuration: 0.1) { [weak self] in
                guard let strong = self else { return }
                strong.progressView.progress = strong.progress
            }
        }
    }
}

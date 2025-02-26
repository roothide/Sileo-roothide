//
//  DepictionMarkdownView.swift
//  Sileo
//
//  Created by CoolStar on 7/6/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import Evander

class DepictionMarkdownViewSlow: DepictionBaseView, CSTextViewActionHandler {
    var attributedString: NSMutableAttributedString?
    var htmlString: String = ""

    let useSpacing: Bool
    let useMargins: Bool

    let heightRequested: Bool

    let textView: CSTextView

    required init?(dictionary: [String: Any], viewController: UIViewController, tintColor: UIColor, isActionable: Bool) {
        guard let markdown = dictionary["markdown"] as? String else {
            return nil
        }
        
        useSpacing = (dictionary["useSpacing"] as? Bool) ?? true
        useMargins = (dictionary["useMargins"] as? Bool) ?? true

        heightRequested = false

        textView = CSTextView(frame: .zero)
        super.init(dictionary: dictionary, viewController: viewController, tintColor: tintColor, isActionable: isActionable)

        textView.backgroundColor = .clear
        addSubview(textView)

        htmlString = markdown

        reloadMarkdown()

        textView.translatesAutoresizingMaskIntoConstraints = false

        let margins: CGFloat = useMargins ? 16 : 0
        let spacing: CGFloat = useSpacing ? 13 : 0
        let bottomSpacing: CGFloat = useSpacing ? 13 : 0
        NSLayoutConstraint.activate([
            textView.leftAnchor.constraint(equalTo: self.leftAnchor, constant: margins),
            textView.rightAnchor.constraint(equalTo: self.rightAnchor, constant: -margins),
            textView.topAnchor.constraint(equalTo: self.topAnchor, constant: spacing),
            textView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -bottomSpacing)
        ])
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(reloadMarkdown),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 13, *) {
            if !UIColor.isTransitionLockedForiOS13Bug {
                self.reloadMarkdown()
            }
        }
    }
    
    @objc func reloadMarkdown() {
        var red = CGFloat(0)
        var green = CGFloat(0)
        var blue = CGFloat(0)
        var alpha = CGFloat(0)
        tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        red *= 255
        green *= 255
        blue *= 255
        
        var textColorString = ""
        if UIColor.isDarkModeEnabled {
            textColorString = "color: white;"
        }
        
        // swiftlint:disable:next line_length
        let htmlString = String(format: "<style>body{font-family: '-apple-system', 'HelveticaNeue'; font-size:12pt;\(textColorString)} a{text-decoration:none; color:rgba(%.0f,%.0f,%.0f,%.2f)}</style>", red, green, blue, alpha).appending(self.htmlString)
        
        loading(String(localizationKey: "Loading"))
        
        DispatchQueue.global().async {
            self.reloadMarkdownInBackground(htmlString)
        }
    }
    
    func loading(_ str: String) {
        let attributedString = NSMutableAttributedString(string: str)
        let textColor: UIColor = UIColor.isDarkModeEnabled ? .white : .black
        attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: attributedString.length))
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributedString.length))

        self.attributedString = attributedString
        self.textView.attributedText = self.attributedString
        self.textView.setNeedsDisplay()
        super.subviewHeightChanged()
    }
    
    func reloadMarkdownInBackground(_ htmlString: String) {
        // swiftlint:disable:next line_length
        do {
            let attributedString = try NSMutableAttributedString(data: htmlString.data(using: .unicode) ?? "".data(using: .utf8)!, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            attributedString.removeAttribute(NSAttributedString.Key("NSOriginalFont"), range: NSRange(location: 0, length: attributedString.length))
            DispatchQueue.main.async {
                self.attributedString = attributedString
                self.textView.attributedText = attributedString
                super.subviewHeightChanged()
            }
        } catch {
            DispatchQueue.main.async {
                self.loading("\(error)")
            }
        }
    }

    override func depictionHeight(width: CGFloat) -> CGFloat {
        let margins: CGFloat = useMargins ? 32 : 0
        let spacing: CGFloat = useSpacing ? 33 : 0

        guard let attributedString = attributedString else {
            return 0
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let targetSize = CGSize(width: width - margins, height: CGFloat.greatestFiniteMagnitude)
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, attributedString.length), nil, targetSize, nil)
        return fitSize.height + spacing
    }

    func process(action: String) -> Bool {
        DepictionButton.processAction(action, parentViewController: self.parentViewController, openExternal: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.updateConstraintsIfNeeded()
    }
}

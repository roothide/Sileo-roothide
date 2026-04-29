//
//  SettingsViewController.swift
//  Sileo
//
//  Created by Skitty on 1/26/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Alderis
import UIKit
import Evander

class SettingsViewController: BaseSettingsViewController, ThemeSelected {
    private var authenticatedProviders: [PaymentProvider] = Array()
    private var unauthenticatedProviders: [PaymentProvider] = Array()
    private var hasLoadedOnce: Bool = false
    private var observer: Any?
    public var themeExpanded = false
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(style: UITableView.Style) {
        super.init(style: style)
    }
    
    deinit {
        guard let obs = observer else { return }
        NotificationCenter.default.removeObserver(obs)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        authenticatedProviders = Array()
        unauthenticatedProviders = Array()
        self.loadProviders()
        
        self.title = "Sileo"
        
        headerView = SettingsIconHeaderView()
        
        observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: PaymentProvider.listUpdateNotificationName),
                                                          object: nil,
                                                          queue: OperationQueue.main) { _ in
            self.loadProviders()
        }
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        NSLog("SileoLog: SettingsViewController viewWillAppear")
    }
    
    override func updateSileoColors() {
        super.updateSileoColors()
        tableView.reloadData()
    }

    func loadProviders() {
        PaymentManager.shared.getAllPaymentProviders { providers in
            self.hasLoadedOnce = true
            
            self.authenticatedProviders = Array()
            self.unauthenticatedProviders = Array()

            for provider in providers {
                if provider.isAuthenticated {
                    self.authenticatedProviders.append(provider)
                } else {
                    self.unauthenticatedProviders.append(provider)
                }
            }
            
            DispatchQueue.main.async {
                self.tableView.reloadSections(IndexSet(integersIn: 0...0), with: UITableView.RowAnimation.automatic)
            }
        }
    }
}

extension SettingsViewController { // UITableViewDataSource
    override func numberOfSections(in tableView: UITableView) -> Int {
        4
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Payment Providers section
            return authenticatedProviders.count + unauthenticatedProviders.count + (hasLoadedOnce ? 0 : 1)
        case 1: // Themes
            return 5
        case 2:
            return 12
        case 3: // About section
            return 5
        default:
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0: // Payment Providers section
            if indexPath.row < authenticatedProviders.count {
                // Authenticated Provider
                let style = UITableViewCell.CellStyle.subtitle
                let id = "PaymentProviderCellIdentifier"
                let cellClass = PaymentProviderTableViewCell.self
                let cell = self.reusableCell(withStyle: style, reuseIdentifier: id, cellClass: cellClass) as? PaymentProviderTableViewCell
                cell?.isAuthenticated = true
                cell?.provider = authenticatedProviders[indexPath.row]
                return cell ?? UITableViewCell()
            } else if indexPath.row - authenticatedProviders.count < unauthenticatedProviders.count {
                // Unauthenticated Provider
                let style = UITableViewCell.CellStyle.subtitle
                let id = "PaymentProviderCellIdentifier"
                let cellClass = PaymentProviderTableViewCell.self
                let cell = self.reusableCell(withStyle: style, reuseIdentifier: id, cellClass: cellClass) as? PaymentProviderTableViewCell
                cell?.provider = unauthenticatedProviders[indexPath.row - authenticatedProviders.count]
                return cell ?? UITableViewCell()
            } else if !hasLoadedOnce && (indexPath.row - authenticatedProviders.count - unauthenticatedProviders.count) == 0 {
                let style = UITableViewCell.CellStyle.subtitle
                let id = "LoadingCellIdentifier"
                let cellClass = SettingsLoadingTableViewCell.self
                let cell = self.reusableCell(withStyle: style, reuseIdentifier: id, cellClass: cellClass) as! SettingsLoadingTableViewCell
                cell.startAnimating()
                return cell
            }
            return UITableViewCell()
        case 1: // Translation Credit Section OR Settings section
            switch indexPath.row {
            case 0:
                let cell = ThemePickerCell(style: .default, reuseIdentifier: "SettingsCellIdentifier")
                cell.values = SileoThemeManager.shared.themeList.map({ $0.name })
                cell.pickerView.selectRow(cell.values.firstIndex(of: SileoThemeManager.shared.currentTheme.name) ?? 0, inComponent: 0, animated: false)
                cell.callback = self
                cell.title.text = String(localizationKey: "Theme")
                cell.subtitle.text = String(localizationKey: cell.values[cell.pickerView.selectedRow(inComponent: 0)])
                cell.backgroundColor = .clear
                cell.title.textColor = .tintColor
                cell.subtitle.textColor = .tintColor
                cell.pickerView.textColor = .sileoLabel
                return cell
            case 1:
                let cell = SettingsColorTableViewCell()
                cell.textLabel?.text = String(localizationKey: "Tint_Color")
                return cell
            case 2:
                let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "ResetTintCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Reset_Tint_Color")
                return cell
            case 3:
                let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "AltIconCell")
                cell.textLabel?.text = String(localizationKey: "Alternate_Icon_Title")
                cell.accessoryType = .disclosureIndicator
                return cell
            case 4:
                let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "CreateTheme")
                cell.textLabel?.text = String(localizationKey: "Manage_Themes")
                cell.accessoryType = .disclosureIndicator
                return cell
            default:
                fatalError("You done goofed")
            }
        case 2:
            if indexPath.row == 11 {
                let cell = self.reusableCell(withStyle: .value1, reuseIdentifier: "SourceManagementCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Source_Management")
                cell.detailTextLabel?.text = "\(RepoManager.shared.disabledRepoList().count)"
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            let cell = SettingsSwitchTableViewCell()
            switch indexPath.row {
            case 0:
                cell.amyPogLabel.text = String(localizationKey: "Swipe_Actions")
                cell.fallback = true
                cell.defaultKey = "SwipeActions"
            case 1:
                cell.amyPogLabel.text = String(localizationKey: "Show_Provisional")
                cell.fallback = true
                cell.defaultKey = "ShowProvisional"
            case 2:
                cell.amyPogLabel.text = String(localizationKey: "iCloud_Profile")
                cell.fallback = true
                cell.defaultKey = "iCloudProfile"
            case 3:
                cell.amyPogLabel.text = String(localizationKey: "Show_Ignored_Updates")
                cell.fallback = true
                cell.defaultKey = "ShowIgnoredUpdates"
            case 4:
                cell.amyPogLabel.text = String(localizationKey: "Auto_Refresh_Sources")
                cell.fallback = true
                cell.defaultKey = "AutoRefreshSources"
            case 5:
                cell.amyPogLabel.text = String(localizationKey: "Auto_Complete_Queue")
                cell.defaultKey = "AutoComplete"
            case 6:
                cell.amyPogLabel.text = String(localizationKey: "Show_Search_History")
                cell.defaultKey = "ShowSearchHistory"
                cell.fallback = true
            case 7:
                cell.amyPogLabel.text = String(localizationKey: "Auto_Show_Queue")
                cell.fallback = true
                cell.defaultKey = "UpgradeAllAutoQueue"
            case 8:
                cell.amyPogLabel.text = String(localizationKey: "Always_Show_Install_Log")
                cell.defaultKey = "AlwaysShowLog"
            case 9:
                cell.amyPogLabel.text = String(localizationKey: "Auto_Confirm_Upgrade_All_Shortcut")
                cell.defaultKey = "AutoConfirmUpgradeAllShortcut"
            case 10:
                cell.amyPogLabel.text = String(localizationKey: "Developer_Mode")
                cell.fallback = false
                cell.defaultKey = "DeveloperMode"
                cell.viewControllerForPresentation = self
            case 11:
                break
            default:
                fatalError("You done goofed")
            }
            cell.sync()
            return cell
        case 3: // About section
            switch indexPath.row {
            case 0:
                let cell = self.reusableCell(withStyle: .value1, reuseIdentifier: "CacheSizeIdenitifer")
                cell.textLabel?.text = String(localizationKey: "Cache_Size")
                cell.detailTextLabel?.text = FileManager.default.sizeString(EvanderNetworking._cacheDirectory)
                return cell
            case 1:
                let cell: UITableViewCell = self.reusableCell(withStyle: UITableViewCell.CellStyle.default, reuseIdentifier: "LicenseCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Sileo_Team")
                cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
                return cell
            case 2:
                let cell: UITableViewCell = self.reusableCell(withStyle: UITableViewCell.CellStyle.default, reuseIdentifier: "LicenseCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Licenses_Page_Title")
                cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
                return cell
            case 3:
                let cell: UITableViewCell = self.reusableCell(withStyle: UITableViewCell.CellStyle.default, reuseIdentifier: "LicenseCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Language")
                cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
                return cell
            case 4:
                let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "LicenseCellIdentifier")
                cell.textLabel?.text = String(localizationKey: "Canister_Policy")
                cell.accessoryType = .disclosureIndicator
                return cell
            default:
                fatalError("You done goofed")
            }
            
        default:
            return UITableViewCell()
        }
    }
        
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 && indexPath.section == 1 {
            themeExpanded = !themeExpanded
            tableView.beginUpdates()
            tableView.endUpdates()
        }

        switch indexPath.section {
        case 0: // Payment Providers section
            if indexPath.row < authenticatedProviders.count {
                // Authenticated Provider
                let provider: PaymentProvider = authenticatedProviders[indexPath.row]
                let profileViewController: PaymentProfileViewController = PaymentProfileViewController(provider: provider)
                self.navigationController?.pushViewController(profileViewController, animated: true)
            } else if indexPath.row - authenticatedProviders.count < unauthenticatedProviders.count {
                // Unauthenticated Provider
                let provider: PaymentProvider = unauthenticatedProviders[indexPath.row - authenticatedProviders.count]
                PaymentAuthenticator.shared.authenticate(provider: provider, window: self.view.window) { error, _ in
                    if error != nil {
                        let title: String = String(localizationKey: "Provider_Auth_Fail.Title", type: .error)
                        self.present(PaymentError.alert(for: error, title: title), animated: true)
                    }
                }
            }
        case 1:
            switch indexPath.row {
            case 1: self.presentAlderis() // Tint color selector
            case 2: SileoThemeManager.shared.resetTintColor() // Tint color reset
            case 3:
#if targetEnvironment(macCatalyst)
                let errorVC = UIAlertController(title: "Not Supported", message: "Alternate Icons are currently not supported in macOS", preferredStyle: .alert)
                errorVC.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { _ in errorVC.dismiss(animated: true) }))
                self.present(errorVC, animated: true)
#else
                let altVC = AltIconTableViewController()
                self.navigationController?.pushViewController(altVC, animated: true)
#endif
            case 4:
                let menuSettingsVC = ThemesSectionViewController(style: .grouped)
                menuSettingsVC.settingsSender = self
                self.navigationController?.pushViewController(menuSettingsVC, animated: true)
            default: break
            }
        case 2:
            if indexPath.row == 11 {
                let sourceManagementVC = SourceManagementSettingsViewController(style: .grouped)
                self.navigationController?.pushViewController(sourceManagementVC, animated: true)
            }
        case 3: // About section
            switch indexPath.row {
            case 0:
                self.cacheClear()
            case 1:
                let teamViewController: SileoTeamViewController = SileoTeamViewController()
                self.navigationController?.pushViewController(teamViewController, animated: true)
            case 2:
                let licensesViewController: LicensesTableViewController = LicensesTableViewController()
                self.navigationController?.pushViewController(licensesViewController, animated: true)
            case 3:
                let languageSelection = LanguageSelectionViewController(style: .grouped)
                self.navigationController?.pushViewController(languageSelection, animated: true)
            case 4:
                let vc = PrivacyViewController.viewController(privacyLink: canisterPrivacyPolicy)
                self.present(vc, animated: true)
            default: break
            }
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: // Payment Providers section
            return String(localizationKey: "Settings_Payment_Provider_Heading")
        case 1:
            return String(localizationKey: "Theme_Settings")
        case 2: // Translation Credit Section OR Settings section
            return String(localizationKey: "Settings")
        case 3: // About section
            return String(localizationKey: "About")
        default:
            return nil
        }
    }
    
    private func cacheClear() {
        let alert = UIAlertController(title: String(localizationKey: "Clear_Cache"),
                                      message: String(format: String(localizationKey: "Clear_Cache_Message"), FileManager.default.sizeString(EvanderNetworking._cacheDirectory)),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .destructive) { _ in
            EvanderNetworking.clearCache()
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel))
        self.present(alert, animated: true)
    }
    
    private func presentAlderis() {
        if #available(iOS 14, *) {
            let colorPickerViewController = UIColorPickerViewController()
            colorPickerViewController.delegate = self
            colorPickerViewController.supportsAlpha = false
            colorPickerViewController.selectedColor = .tintColor
            self.present(colorPickerViewController, animated: true)
        } else {
            let colorPickerViewController = ColorPickerViewController()
            colorPickerViewController.delegate = self
            colorPickerViewController.configuration = ColorPickerConfiguration(color: .tintColor)
            if UIDevice.current.userInterfaceIdiom == .pad {
                if #available(iOS 13, *) {
                    colorPickerViewController.popoverPresentationController?.sourceView = self.navigationController?.view
                }
            }
            colorPickerViewController.modalPresentationStyle = .overFullScreen
            self.parent?.present(colorPickerViewController, animated: true, completion: nil)
        }
        
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == 0 && indexPath.section == 1 {
            return !themeExpanded ? 44 : 160
        }
        
        let auth = authenticatedProviders.count
        let unauth = unauthenticatedProviders.count
        if indexPath.section == 0 && (indexPath.row < auth || indexPath.row - auth < unauth) {
            return 54
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    func themeSelected(_ index: Int) {
        SileoThemeManager.shared.activate(theme: SileoThemeManager.shared.themeList[index])
    }

}

extension SettingsViewController: ColorPickerDelegate {
    func colorPicker(_ colorPicker: ColorPickerViewController, didSelect color: UIColor) {
        SileoThemeManager.shared.setTintColor(color)
    }
}

@available(iOS 14.0, *)
extension SettingsViewController: UIColorPickerViewControllerDelegate {

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        SileoThemeManager.shared.setTintColor(viewController.selectedColor)
    }
    
}

final class SourceManagementSettingsViewController: BaseSettingsViewController {
    private enum Row: Int, CaseIterable {
        case timeout
        case concurrency
        case timeoutAutoDisableToggle
        case timeoutAutoDisableThreshold
        case httpErrorAutoDisableToggle
        case httpErrorAutoDisableThreshold
        case disabledSources
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = String(localizationKey: "Source_Management")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localizationKey: "Sources_Page")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = Row(rawValue: indexPath.row) else {
            return UITableViewCell()
        }
        if row == .timeoutAutoDisableToggle || row == .httpErrorAutoDisableToggle {
            let cell = self.reusableCell(withStyle: .default,
                                         reuseIdentifier: "SourceManagementSwitchCell",
                                         cellClass: SourceManagementSwitchTableViewCell.self) as? SourceManagementSwitchTableViewCell ?? SourceManagementSwitchTableViewCell(style: .default, reuseIdentifier: "SourceManagementSwitchCell")
            cell.onToggle = { [weak self] isOn in
                self?.handleToggleChange(for: row, isOn: isOn)
            }
            switch row {
            case .timeoutAutoDisableToggle:
                cell.amyPogLabel.text = String(localizationKey: "Source_Auto_Disable_On_Timeouts")
                cell.control.isOn = RepoRefreshSettings.timeoutAutoDisableEnabled
            case .httpErrorAutoDisableToggle:
                cell.amyPogLabel.text = String(localizationKey: "Source_Auto_Disable_On_HTTP_Errors")
                cell.control.isOn = RepoRefreshSettings.httpErrorAutoDisableEnabled
            default:
                break
            }
            return cell
        }

        let cell = self.reusableCell(withStyle: .value1, reuseIdentifier: "SourceManagementSettingCell")
        cell.accessoryType = .disclosureIndicator
        switch row {
        case .timeout:
            cell.textLabel?.text = String(localizationKey: "Source_Refresh_Timeout")
            cell.detailTextLabel?.text = "\(Int(RepoRefreshSettings.timeoutSeconds))s"
        case .concurrency:
            cell.textLabel?.text = String(localizationKey: "Source_Refresh_Concurrency")
            let override = RepoRefreshSettings.concurrencyOverride
            cell.detailTextLabel?.text = override == 0 ? String(localizationKey: "Auto") : "\(override)"
        case .timeoutAutoDisableThreshold:
            cell.textLabel?.text = String(localizationKey: "Source_Auto_Disable_After_Timeouts")
            let threshold = RepoRefreshSettings.autoDisableAfterTimeouts
            cell.detailTextLabel?.text = threshold == 0 ? String(localizationKey: "Never") : "\(threshold)"
        case .httpErrorAutoDisableThreshold:
            cell.textLabel?.text = String(localizationKey: "Source_Auto_Disable_After_HTTP_Errors")
            let threshold = RepoRefreshSettings.autoDisableAfterHTTPErrors
            cell.detailTextLabel?.text = threshold == 0 ? String(localizationKey: "Never") : "\(threshold)"
        case .disabledSources:
            cell.textLabel?.text = String(localizationKey: "Disabled_Sources")
            cell.detailTextLabel?.text = "\(RepoManager.shared.disabledRepoList().count)"
        default:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = Row(rawValue: indexPath.row) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        switch row {
        case .timeout:
            presentIntegerEditor(title: String(localizationKey: "Source_Refresh_Timeout"),
                                 message: String(localizationKey: "Source_Management_Timeout_Prompt"),
                                 currentValue: "\(Int(RepoRefreshSettings.timeoutSeconds))",
                                 allowZero: false) { value in
                RepoRefreshSettings.setTimeoutSeconds(value)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .concurrency:
            presentIntegerEditor(title: String(localizationKey: "Source_Refresh_Concurrency"),
                                 message: String(localizationKey: "Source_Management_Concurrency_Prompt"),
                                 currentValue: "\(RepoRefreshSettings.concurrencyOverride)",
                                 allowZero: true) { value in
                RepoRefreshSettings.setConcurrencyOverride(value)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .timeoutAutoDisableThreshold:
            presentIntegerEditor(title: String(localizationKey: "Source_Auto_Disable_After_Timeouts"),
                                 message: String(localizationKey: "Source_Management_Auto_Disable_Prompt"),
                                 currentValue: "\(RepoRefreshSettings.autoDisableAfterTimeouts)",
                                 allowZero: true) { value in
                RepoRefreshSettings.setAutoDisableAfterTimeouts(value)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .httpErrorAutoDisableThreshold:
            presentIntegerEditor(title: String(localizationKey: "Source_Auto_Disable_After_HTTP_Errors"),
                                 message: String(localizationKey: "Source_Management_HTTP_Error_Prompt"),
                                 currentValue: "\(RepoRefreshSettings.autoDisableAfterHTTPErrors)",
                                 allowZero: true) { value in
                RepoRefreshSettings.setAutoDisableAfterHTTPErrors(value)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .disabledSources:
            let disabledSourcesVC = DisabledSourcesViewController(style: .grouped)
            self.navigationController?.pushViewController(disabledSourcesVC, animated: true)
        case .timeoutAutoDisableToggle, .httpErrorAutoDisableToggle:
            break
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func handleToggleChange(for row: Row, isOn: Bool) {
        switch row {
        case .timeoutAutoDisableToggle:
            RepoRefreshSettings.setTimeoutAutoDisableEnabled(isOn)
            RepoManager.shared.updateAutoDisablePreference(for: .autoTimeout, enabled: isOn)
        case .httpErrorAutoDisableToggle:
            RepoRefreshSettings.setHTTPErrorAutoDisableEnabled(isOn)
            RepoManager.shared.updateAutoDisablePreference(for: .autoHTTPError, enabled: isOn)
        default:
            return
        }
        tableView.reloadData()
    }

    private func presentIntegerEditor(title: String, message: String, currentValue: String, allowZero: Bool, onSave: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.text = currentValue
        }
        alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .default) { _ in
            guard let rawValue = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Int(rawValue),
                  allowZero ? value >= 0 : value > 0 else {
                return
            }
            onSave(value)
        })
        self.present(alert, animated: true)
    }
}

final class SourceManagementSwitchTableViewCell: SettingsSwitchTableViewCell {
    var onToggle: ((Bool) -> Void)?

    override func didChange(sender: UISwitch!) {
        onToggle?(sender.isOn)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggle = nil
    }
}

final class DisabledSourcesSectionHeaderView: UIView {
    private enum ActionsLayoutMode {
        case singleRow
        case twoRows
        case vertical
    }

    private let titleLabel = SileoLabelView()
    private let actionsRowsStackView = UIStackView()
    private let topActionsStackView = UIStackView()
    private let middleActionsStackView = UIStackView()
    private let bottomActionsStackView = UIStackView()
    private let enableButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let buttonHeight: CGFloat = 30
    private let buttonSpacing: CGFloat = 8
    private var actionsLayoutMode: ActionsLayoutMode?

    init(title: String,
         actionsEnabled: Bool,
         canRemove: Bool,
         enableAction: UIAction,
         refreshAction: UIAction,
         removeAction: UIAction) {
        super.init(frame: .zero)

        preservesSuperviewLayoutMargins = true
        insetsLayoutMarginsFromSafeArea = true
        layoutMargins = UIEdgeInsets(top: 16, left: layoutMargins.left, bottom: 8, right: layoutMargins.right)

        let contentStackView = UIStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 8

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        actionsRowsStackView.translatesAutoresizingMaskIntoConstraints = false
        actionsRowsStackView.axis = .vertical
        actionsRowsStackView.alignment = .fill
        actionsRowsStackView.spacing = buttonSpacing

        [topActionsStackView, middleActionsStackView, bottomActionsStackView].forEach { stackView in
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .horizontal
            stackView.alignment = .fill
            stackView.distribution = .fillEqually
            stackView.spacing = buttonSpacing
            actionsRowsStackView.addArrangedSubview(stackView)
        }

        configureActionButton(enableButton,
                              title: String(localizationKey: "Enable"),
                              action: enableAction,
                              enabled: actionsEnabled)
        configureActionButton(refreshButton,
                              title: String(localizationKey: "Refresh"),
                              action: refreshAction,
                              enabled: actionsEnabled)
        configureActionButton(removeButton,
                              title: String(localizationKey: "Remove"),
                              action: removeAction,
                              enabled: actionsEnabled && canRemove)

        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(actionsRowsStackView)
        addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])

        applyActionsLayout(.singleRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateActionsLayoutIfNeeded()
    }

    private func configureActionButton(_ button: UIButton, title: String, action: UIAction, enabled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.addAction(action, for: .touchUpInside)
        button.isEnabled = enabled
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
    }

    private func clearArrangedSubviews(from stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func configureRow(_ stackView: UIStackView, buttons: [UIButton]) {
        clearArrangedSubviews(from: stackView)
        stackView.isHidden = buttons.isEmpty
        buttons.forEach { stackView.addArrangedSubview($0) }
    }

    private func applyActionsLayout(_ mode: ActionsLayoutMode) {
        guard actionsLayoutMode != mode else {
            return
        }

        switch mode {
        case .singleRow:
            configureRow(topActionsStackView, buttons: [enableButton, refreshButton, removeButton])
            configureRow(middleActionsStackView, buttons: [])
            configureRow(bottomActionsStackView, buttons: [])
        case .twoRows:
            configureRow(topActionsStackView, buttons: [enableButton, refreshButton])
            configureRow(middleActionsStackView, buttons: [removeButton])
            configureRow(bottomActionsStackView, buttons: [])
        case .vertical:
            configureRow(topActionsStackView, buttons: [enableButton])
            configureRow(middleActionsStackView, buttons: [refreshButton])
            configureRow(bottomActionsStackView, buttons: [removeButton])
        }

        actionsLayoutMode = mode
        invalidateIntrinsicContentSize()
    }

    private func preferredActionsLayoutMode(for availableWidth: CGFloat) -> ActionsLayoutMode {
        guard availableWidth > 0 else {
            return .singleRow
        }

        let buttonWidths = [enableButton, refreshButton, removeButton].map {
            $0.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: buttonHeight)).width + 16
        }

        let singleRowWidth = buttonWidths.reduce(0, +) + (buttonSpacing * 2)
        if availableWidth >= singleRowWidth {
            return .singleRow
        }

        let twoRowsWidth = max(buttonWidths[0] + buttonSpacing + buttonWidths[1], buttonWidths[2])
        if availableWidth >= twoRowsWidth {
            return .twoRows
        }

        return .vertical
    }

    private func updateActionsLayoutIfNeeded() {
        let availableWidth = layoutMarginsGuide.layoutFrame.width
        let preferredMode = preferredActionsLayoutMode(for: availableWidth)
        guard preferredMode != actionsLayoutMode else {
            return
        }
        applyActionsLayout(preferredMode)
        setNeedsLayout()
    }
}

final class DisabledSourcesViewController: BaseSettingsViewController {
    private struct DisabledSourceSection {
        let id: String
        let title: String
        let repos: [Repo]
    }

    private var activeRefreshSectionID: String?

    private func conciseAutoDisabledSectionTitle(localizationKey: String) -> String {
        let fullTitle = String(localizationKey: localizationKey)
        if let suffix = fullTitle.components(separatedBy: " - ").last,
           fullTitle.contains(" - ") {
            return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fullTitle
    }

    private var disabledSections: [DisabledSourceSection] {
        let disabledRepos = RepoManager.shared.sortedRepoList(repos: RepoManager.shared.disabledRepoList())
        var manualRepos = [Repo]()
        var autoTimeoutRepos = [Repo]()
        var autoHTTPReposByStatus = [Int: [Repo]]()
        var autoHTTPReposWithoutStatus = [Repo]()

        for repo in disabledRepos {
            let state = RepoManager.shared.refreshState(for: repo)
            if state.isManualDisabled {
                manualRepos.append(repo)
            } else if state.isTimeoutAutoDisabled {
                autoTimeoutRepos.append(repo)
            } else if state.isHTTPErrorAutoDisabled {
                if let statusCode = state.lastHTTPStatusCode {
                    autoHTTPReposByStatus[statusCode, default: []].append(repo)
                } else {
                    autoHTTPReposWithoutStatus.append(repo)
                }
            }
        }

        var sections = [DisabledSourceSection]()
        if !manualRepos.isEmpty {
            sections.append(DisabledSourceSection(id: "manual",
                                                  title: String(localizationKey: "Disabled_Sources_Manual_Section"),
                                                  repos: manualRepos))
        }
        if !autoTimeoutRepos.isEmpty {
            sections.append(DisabledSourceSection(id: "auto-timeout",
                                                  title: conciseAutoDisabledSectionTitle(localizationKey: "Disabled_Sources_Auto_Timeout_Section"),
                                                  repos: autoTimeoutRepos))
        }

        let autoHTTPSectionTitle = conciseAutoDisabledSectionTitle(localizationKey: "Disabled_Sources_Auto_HTTP_Section")
        for statusCode in autoHTTPReposByStatus.keys.sorted() {
            guard let repos = autoHTTPReposByStatus[statusCode], !repos.isEmpty else {
                continue
            }
            sections.append(DisabledSourceSection(id: "auto-http-\(statusCode)",
                                                  title: "\(autoHTTPSectionTitle)\nHTTP \(statusCode)",
                                                  repos: repos))
        }
        if !autoHTTPReposWithoutStatus.isEmpty {
            sections.append(DisabledSourceSection(id: "auto-http-unknown",
                                                  title: autoHTTPSectionTitle,
                                                  repos: autoHTTPReposWithoutStatus))
        }
        return sections
    }

    private func displayTitle(for repo: Repo) -> String {
        repo.repoName.isEmpty ? repo.displayURL : repo.displayName
    }

    private func detailText(state: RepoManager.RepoRefreshState) -> String {
        if state.isManualDisabled {
            return String(localizationKey: "Source_Disabled_Manual")
        }
        if state.isTimeoutAutoDisabled {
            let threshold = max(1, RepoRefreshSettings.autoDisableAfterTimeouts)
            let timeoutCount = state.consecutiveTimeoutCount > 0 ? state.consecutiveTimeoutCount : threshold
            return String(format: String(localizationKey: "Source_Disabled_AutoTimeout"), timeoutCount)
        }
        if state.isHTTPErrorAutoDisabled {
            let threshold = max(1, RepoRefreshSettings.autoDisableAfterHTTPErrors)
            let errorCount = state.consecutiveHTTPErrorCount > 0 ? state.consecutiveHTTPErrorCount : threshold
            if let statusCode = state.lastHTTPStatusCode {
                return String(format: String(localizationKey: "Source_Disabled_AutoHTTPStatus"), errorCount, statusCode)
            }
            return String(format: String(localizationKey: "Source_Disabled_AutoHTTPStatus_Generic"), errorCount)
        }
        return state.lastFailureReason ?? String(localizationKey: "Source_Disabled_Manual")
    }

    private func repo(at indexPath: IndexPath) -> Repo? {
        let sections = disabledSections
        guard !sections.isEmpty else {
            return nil
        }
        return sections[indexPath.section].repos[indexPath.row]
    }

    private func repos(in section: Int) -> [Repo] {
        let sections = disabledSections
        guard !sections.isEmpty, sections.indices.contains(section) else {
            return []
        }
        return sections[section].repos
    }

    private func removableRepos(in section: Int) -> [Repo] {
        repos(in: section).filter(canRemove)
    }

    private func refreshSucceeded(repo: Repo, previousSuccessAt: Date?) -> Bool {
        guard let currentSuccessAt = RepoManager.shared.refreshState(for: repo).lastSuccessAt else {
            return false
        }
        guard let previousSuccessAt else {
            return true
        }
        return currentSuccessAt > previousSuccessAt
    }

    private func presentRefreshErrors(_ errorOutput: NSAttributedString) {
        let errorVC = SourcesErrorsViewController(nibName: "SourcesErrorsViewController", bundle: nil)
        errorVC.attributedString = errorOutput
        self.present(errorVC, animated: true)
    }

    private func enableSection(_ section: Int) {
        guard !DownloadManager.shared.queueRunning else {
            TabBarController.singleton?.presentPopupController()
            return
        }
        for repo in repos(in: section) {
            RepoManager.shared.enableRepo(repo)
        }
        tableView.reloadData()
    }

    private func removeSection(_ section: Int) {
        let removableRepos = removableRepos(in: section)
        guard !removableRepos.isEmpty else {
            return
        }
        guard !DownloadManager.shared.queueRunning else {
            TabBarController.singleton?.presentPopupController()
            return
        }
        for repo in removableRepos {
            RepoManager.shared.remove(repo: repo)
        }
        tableView.reloadData()
    }

    private func refreshSection(_ section: Int) {
        let repos = repos(in: section)
        guard !repos.isEmpty, activeRefreshSectionID == nil else {
            return
        }

        let previousSuccessByRepo = Dictionary(uniqueKeysWithValues: repos.map {
            ($0.refreshStateKey, RepoManager.shared.refreshState(for: $0).lastSuccessAt)
        })

        activeRefreshSectionID = disabledSections[section].id
        tableView.reloadData()

        RepoManager.shared.update(force: false,
                                  forceReload: true,
                                  isBackground: false,
                                  selectionMode: .explicit,
                                  repos: repos) { didFindErrors, errorOutput in
            for repo in repos {
                let previousSuccessAt = previousSuccessByRepo[repo.refreshStateKey] ?? nil
                if self.refreshSucceeded(repo: repo, previousSuccessAt: previousSuccessAt),
                   RepoManager.shared.isRepoDisabled(repo) {
                    RepoManager.shared.enableRepo(repo)
                }
            }

            self.activeRefreshSectionID = nil
            self.tableView.reloadData()

            if didFindErrors, errorOutput.length > 0 {
                self.presentRefreshErrors(errorOutput)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = String(localizationKey: "Disabled_Sources")
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 112
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        max(disabledSections.count, 1)
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sections = disabledSections
        guard !sections.isEmpty else {
            return super.tableView(tableView, viewForHeaderInSection: section)
        }

        let sectionInfo = sections[section]
        let isRefreshing = activeRefreshSectionID == sectionInfo.id
        return DisabledSourcesSectionHeaderView(
            title: sectionInfo.title,
            actionsEnabled: !isRefreshing,
            canRemove: !removableRepos(in: section).isEmpty,
            enableAction: UIAction { [weak self] _ in
                self?.enableSection(section)
            },
            refreshAction: UIAction { [weak self] _ in
                self?.refreshSection(section)
            },
            removeAction: UIAction { [weak self] _ in
                self?.removeSection(section)
            }
        )
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        disabledSections.isEmpty ? super.tableView(tableView, heightForHeaderInSection: section) : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        disabledSections.isEmpty ? super.tableView(tableView, estimatedHeightForHeaderInSection: section) : 112
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = disabledSections
        guard !sections.isEmpty else {
            return 1
        }
        return sections[section].repos.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sections = disabledSections
        return sections.isEmpty ? String(localizationKey: "Disabled_Sources") : sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sections = disabledSections
        if sections.isEmpty {
            let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "DisabledSourcesEmptyCell")
            cell.textLabel?.text = String(localizationKey: "Disabled_Sources_Empty")
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }

        let repo = sections[indexPath.section].repos[indexPath.row]
        let state = RepoManager.shared.refreshState(for: repo)
        let cell = self.reusableCell(withStyle: .subtitle, reuseIdentifier: "DisabledSourceCell")
        cell.textLabel?.text = displayTitle(for: repo)
        cell.detailTextLabel?.text = detailText(state: state)
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let repo = repo(at: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        let alert = UIAlertController(title: displayTitle(for: repo), message: repo.repoName.isEmpty ? nil : repo.displayURL, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localizationKey: "Enable"), style: .default) { _ in
            guard !DownloadManager.shared.queueRunning else {
                TabBarController.singleton?.presentPopupController()
                return
            }
            RepoManager.shared.enableRepo(repo)
            self.tableView.reloadData()
        })
        if self.canRemove(repo) {
            alert.addAction(UIAlertAction(title: String(localizationKey: "Remove"), style: .destructive) { _ in
                guard !DownloadManager.shared.queueRunning else {
                    TabBarController.singleton?.presentPopupController()
                    return
                }
                RepoManager.shared.remove(repo: repo)
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        self.present(alert, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func canRemove(_ repo: Repo) -> Bool {
        if Jailbreak.bootstrap == .procursus {
            return repo.entryFile.hasSuffix("/sileo.sources")
        }
        return repo.url?.host != "apt.bingner.com"
    }
}

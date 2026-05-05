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
        case http522Treatment
        case exportSources
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
        case .http522Treatment:
            cell.textLabel?.text = String(localizationKey: "Source_HTTP_522_Treatment")
            switch RepoRefreshSettings.http522Treatment {
            case .websiteError:
                cell.detailTextLabel?.text = String(localizationKey: "Source_HTTP_522_Treatment_Website_Error")
            case .timeout:
                cell.detailTextLabel?.text = String(localizationKey: "Source_HTTP_522_Treatment_Timeout")
            }
        case .exportSources:
            cell.textLabel?.text = String(localizationKey: "Source_Management_Export_Sources")
            cell.detailTextLabel?.text = nil
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
            let promptLocalizationKey = RepoRefreshSettings.http522Treatment == .websiteError
                ? "Source_Management_HTTP_Error_Prompt"
                : "Source_Management_HTTP_Error_Prompt_Without_522"
            presentIntegerEditor(title: String(localizationKey: "Source_Auto_Disable_After_HTTP_Errors"),
                                 message: String(localizationKey: promptLocalizationKey),
                                 currentValue: "\(RepoRefreshSettings.autoDisableAfterHTTPErrors)",
                                 allowZero: true) { value in
                RepoRefreshSettings.setAutoDisableAfterHTTPErrors(value)
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        case .http522Treatment:
            presentHTTP522TreatmentSelector(sourceView: tableView.cellForRow(at: indexPath), indexPath: indexPath)
        case .exportSources:
            SourcesExportUI.presentExportOptions(from: self, sender: tableView.cellForRow(at: indexPath))
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

    private func presentHTTP522TreatmentSelector(sourceView: UIView?, indexPath: IndexPath) {
        let alert = UIAlertController(title: String(localizationKey: "Source_HTTP_522_Treatment"),
                                      message: String(localizationKey: "Source_HTTP_522_Treatment_Message"),
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localizationKey: "Source_HTTP_522_Treatment_Website_Error"), style: .default) { _ in
            RepoManager.shared.updateHTTP522Treatment(.websiteError)
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
        })
        alert.addAction(UIAlertAction(title: String(localizationKey: "Source_HTTP_522_Treatment_Timeout"), style: .default) { _ in
            RepoManager.shared.updateHTTP522Treatment(.timeout)
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
        })
        alert.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            if let sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX,
                                            y: self.view.bounds.midY,
                                            width: 0,
                                            height: 0)
            }
        }
        self.present(alert, animated: true)
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

final class DisabledSourcesSectionHeaderView: UITableViewHeaderFooterView {
    struct Configuration: Equatable {
        let title: String
        let subtitle: String?
        let actionsEnabled: Bool
        let canRemove: Bool
    }

    static let reuseIdentifier = "DisabledSourcesSectionHeaderView"

    private enum ActionsLayoutMode {
        case singleRow
        case twoRows
        case vertical
    }

    private let titleLabel = SileoLabelView()
    private let textStackView = UIStackView()
    private let subtitleLabel = UILabel()
    private let actionsRowsStackView = UIStackView()
    private let topActionsStackView = UIStackView()
    private let middleActionsStackView = UIStackView()
    private let bottomActionsStackView = UIStackView()
    private let enableButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let buttonHeight: CGFloat = 34
    private let buttonSpacing: CGFloat = 8
    private var actionsLayoutMode: ActionsLayoutMode?
    private var onEnable: (() -> Void)?
    private var onRefresh: (() -> Void)?
    private var onRemove: (() -> Void)?
    private var currentConfiguration: Configuration?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        contentView.preservesSuperviewLayoutMargins = true
        contentView.insetsLayoutMarginsFromSafeArea = true
        contentView.layoutMargins = UIEdgeInsets(top: 16, left: contentView.layoutMargins.left, bottom: 8, right: contentView.layoutMargins.right)
        backgroundView = UIView()
        backgroundView?.backgroundColor = .clear
        textLabel?.isHidden = true
        detailTextLabel?.isHidden = true

        let contentStackView = UIStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 10

        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.axis = .vertical
        textStackView.alignment = .fill
        textStackView.spacing = 4

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.isHidden = true

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
                              selector: #selector(enableButtonTapped))
        configureActionButton(refreshButton,
                              title: String(localizationKey: "Refresh"),
                              selector: #selector(refreshButtonTapped))
        configureActionButton(removeButton,
                              title: String(localizationKey: "Remove"),
                              selector: #selector(removeButtonTapped))

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)
        contentStackView.addArrangedSubview(textStackView)
        contentStackView.addArrangedSubview(actionsRowsStackView)
        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        ])

        applyActionsLayout(.singleRow)
        updateActionButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onEnable = nil
        onRefresh = nil
        onRemove = nil
        currentConfiguration = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableTextWidth = contentView.layoutMarginsGuide.layoutFrame.width
        if titleLabel.preferredMaxLayoutWidth != availableTextWidth {
            titleLabel.preferredMaxLayoutWidth = availableTextWidth
        }
        if subtitleLabel.preferredMaxLayoutWidth != availableTextWidth {
            subtitleLabel.preferredMaxLayoutWidth = availableTextWidth
        }
        updateActionsLayoutIfNeeded()
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                          withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        let fittingWidth = targetSize.width > 0 ? targetSize.width : bounds.width
        if fittingWidth > 0 {
            let availableTextWidth = max(0, fittingWidth - contentView.layoutMargins.left - contentView.layoutMargins.right)
            titleLabel.preferredMaxLayoutWidth = availableTextWidth
            subtitleLabel.preferredMaxLayoutWidth = availableTextWidth
        }
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()

        let size = contentView.systemLayoutSizeFitting(CGSize(width: fittingWidth,
                                                              height: UIView.layoutFittingCompressedSize.height),
                                                       withHorizontalFittingPriority: .required,
                                                       verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: fittingWidth, height: size.height)
    }

    func configure(configuration: Configuration,
                   onEnable: @escaping () -> Void,
                   onRefresh: @escaping () -> Void,
                   onRemove: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onRefresh = onRefresh
        self.onRemove = onRemove

        guard currentConfiguration != configuration else {
            return
        }

        let previousConfiguration = currentConfiguration
        currentConfiguration = configuration
        if previousConfiguration?.title != configuration.title ||
            previousConfiguration?.subtitle != configuration.subtitle {
            updateTextLabels(configuration: configuration)
            setNeedsLayout()
        }
        if previousConfiguration?.actionsEnabled != configuration.actionsEnabled {
            enableButton.isEnabled = configuration.actionsEnabled
            refreshButton.isEnabled = configuration.actionsEnabled
        }

        let removeButtonEnabled = configuration.actionsEnabled && configuration.canRemove
        let previousRemoveButtonEnabled = previousConfiguration.map { $0.actionsEnabled && $0.canRemove }
        if previousRemoveButtonEnabled != removeButtonEnabled {
            removeButton.isEnabled = removeButtonEnabled
        }
        updateActionButtonStyles()
        accessibilityLabel = [configuration.title, configuration.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func configureActionButton(_ button: UIButton, title: String, selector: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.clipsToBounds = true
        button.layer.cornerRadius = 12
        if #available(iOS 13.0, *) {
            button.layer.cornerCurve = .continuous
        }
        button.addTarget(self, action: selector, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
    }

    private func updateTextLabels(configuration: Configuration) {
        titleLabel.text = configuration.title
        if let subtitle = configuration.subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.text = nil
            subtitleLabel.isHidden = true
        }
    }

    private func actionButtonBaseColor(for button: UIButton) -> UIColor {
        if button === enableButton {
            return .tintColor
        }
        if button === refreshButton {
            return .systemGreen
        }
        return .systemRed
    }

    private func updateActionButtonStyles() {
        [enableButton, refreshButton, removeButton].forEach(updateActionButtonStyle)
    }

    private func updateActionButtonStyle(_ button: UIButton) {
        let baseColor = actionButtonBaseColor(for: button)
        let isEnabled = button.isEnabled
        button.backgroundColor = isEnabled ? baseColor.withAlphaComponent(0.12) : UIColor.tertiarySystemFill
        button.layer.borderWidth = 1
        button.layer.borderColor = (isEnabled ? baseColor.withAlphaComponent(0.24) : UIColor.separator.withAlphaComponent(0.35)).cgColor
        button.setTitleColor(isEnabled ? baseColor : UIColor.secondaryLabel, for: .normal)
        button.alpha = isEnabled ? 1 : 0.82
    }

    @objc private func enableButtonTapped() {
        onEnable?()
    }

    @objc private func refreshButtonTapped() {
        onRefresh?()
    }

    @objc private func removeButtonTapped() {
        onRemove?()
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
        let availableWidth = contentView.layoutMarginsGuide.layoutFrame.width
        let preferredMode = preferredActionsLayoutMode(for: availableWidth)
        guard preferredMode != actionsLayoutMode else {
            return
        }
        applyActionsLayout(preferredMode)
        setNeedsLayout()
    }
}

final class DisabledSourcesViewController: BaseSettingsViewController {
    private struct DisabledSourceSection: Equatable {
        let id: String
        let title: String
        let subtitle: String?
        let repos: [Repo]
    }

    private var activeRefreshSectionID: String?
    private var disabledSectionsSnapshot = [DisabledSourceSection]()
    private var disabledSourcesObserver: Any?
    private var disabledSectionsReloadWorkItem: DispatchWorkItem?
    private var disabledSectionsNeedsForceReload = false
    private var disabledSectionsPendingSectionIDs = Set<String>()
    private let disabledSectionsReloadDebounceInterval: TimeInterval = 0.05
    private var renderedActiveRefreshSectionID: String?

    private func conciseAutoDisabledSectionTitle(localizationKey: String) -> String {
        let fullTitle = String(localizationKey: localizationKey)
        if let suffix = fullTitle.components(separatedBy: " - ").last,
           fullTitle.contains(" - ") {
            return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fullTitle
    }

    private func buildDisabledSectionsSnapshot() -> [DisabledSourceSection] {
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
                                                  subtitle: nil,
                                                  repos: manualRepos))
        }
        if !autoTimeoutRepos.isEmpty {
            sections.append(DisabledSourceSection(id: "auto-timeout",
                                                  title: conciseAutoDisabledSectionTitle(localizationKey: "Disabled_Sources_Auto_Timeout_Section"),
                                                  subtitle: nil,
                                                  repos: autoTimeoutRepos))
        }

        let autoHTTPSectionTitle = conciseAutoDisabledSectionTitle(localizationKey: "Disabled_Sources_Auto_HTTP_Section")
        for statusCode in autoHTTPReposByStatus.keys.sorted() {
            guard let repos = autoHTTPReposByStatus[statusCode], !repos.isEmpty else {
                continue
            }
            sections.append(DisabledSourceSection(id: "auto-http-\(statusCode)",
                                                  title: autoHTTPSectionTitle,
                                                  subtitle: "HTTP \(statusCode)",
                                                  repos: repos))
        }
        if !autoHTTPReposWithoutStatus.isEmpty {
            sections.append(DisabledSourceSection(id: "auto-http-unknown",
                                                  title: autoHTTPSectionTitle,
                                                  subtitle: nil,
                                                  repos: autoHTTPReposWithoutStatus))
        }
        return sections
    }

    private func sectionIndexes(for sectionIDs: Set<String>, in snapshot: [DisabledSourceSection]) -> IndexSet {
        var indexes = IndexSet()
        for (index, section) in snapshot.enumerated() where sectionIDs.contains(section.id) {
            indexes.insert(index)
        }
        return indexes
    }

    private func headerConfiguration(for section: DisabledSourceSection,
                                     activeRefreshSectionID: String?) -> DisabledSourcesSectionHeaderView.Configuration {
        let isRefreshing = activeRefreshSectionID == section.id
        return DisabledSourcesSectionHeaderView.Configuration(title: section.title,
                                                             subtitle: section.subtitle,
                                                             actionsEnabled: !isRefreshing,
                                                             canRemove: section.repos.contains(where: canRemove))
    }

    private func configureHeaderView(_ headerView: DisabledSourcesSectionHeaderView, section: DisabledSourceSection) {
        headerView.configure(configuration: headerConfiguration(for: section, activeRefreshSectionID: activeRefreshSectionID),
                             onEnable: { [weak self] in
                                 self?.enableSection(section.id)
                             },
                             onRefresh: { [weak self] in
                                 self?.refreshSection(section.id)
                             },
                             onRemove: { [weak self] in
                                 self?.removeSection(section.id)
                             })
    }

    private func reconfigureVisibleHeaders(for sectionIDs: Set<String>,
                                           in snapshot: [DisabledSourceSection]) -> Set<String> {
        var reconfiguredSectionIDs = Set<String>()
        for sectionID in sectionIDs {
            guard let sectionIndex = snapshot.firstIndex(where: { $0.id == sectionID }),
                  let headerView = tableView.headerView(forSection: sectionIndex) as? DisabledSourcesSectionHeaderView else {
                continue
            }
            configureHeaderView(headerView, section: snapshot[sectionIndex])
            reconfiguredSectionIDs.insert(sectionID)
        }
        return reconfiguredSectionIDs
    }

    private func applyDisabledSectionsSnapshotIfNeeded(forceReload: Bool = false) {
        let previousSnapshot = disabledSectionsSnapshot
        let previousActiveRefreshSectionID = renderedActiveRefreshSectionID
        let snapshot = buildDisabledSectionsSnapshot()
        let structureChanged = previousSnapshot.map(\.id) != snapshot.map(\.id)

        var changedSectionIDs = Set<String>()
        var headerOnlySectionIDs = Set<String>()
        var headerLayoutChangedSectionIDs = Set<String>()
        if !structureChanged {
            for (oldSection, newSection) in zip(previousSnapshot, snapshot) {
                let previousHeaderConfiguration = headerConfiguration(for: oldSection,
                                                                     activeRefreshSectionID: previousActiveRefreshSectionID)
                let currentHeaderConfiguration = headerConfiguration(for: newSection,
                                                                    activeRefreshSectionID: activeRefreshSectionID)
                if oldSection.repos != newSection.repos {
                    changedSectionIDs.insert(newSection.id)
                } else if previousHeaderConfiguration != currentHeaderConfiguration {
                    headerOnlySectionIDs.insert(newSection.id)
                    if previousHeaderConfiguration.title != currentHeaderConfiguration.title ||
                        previousHeaderConfiguration.subtitle != currentHeaderConfiguration.subtitle {
                        headerLayoutChangedSectionIDs.insert(newSection.id)
                    }
                }
            }
        }

        headerOnlySectionIDs.formUnion(disabledSectionsPendingSectionIDs)
        disabledSectionsPendingSectionIDs.removeAll()
        disabledSectionsSnapshot = snapshot
        renderedActiveRefreshSectionID = activeRefreshSectionID

        if snapshot.isEmpty {
            tableView.reloadData()
            return
        }

        if structureChanged || previousSnapshot.isEmpty != snapshot.isEmpty {
            tableView.reloadData()
            return
        }

        if tableView.numberOfSections == 0 {
            tableView.reloadData()
            return
        }

        headerOnlySectionIDs.subtract(changedSectionIDs)

        let reconfiguredHeaderSectionIDs = reconfigureVisibleHeaders(for: headerOnlySectionIDs, in: snapshot)
        if !headerLayoutChangedSectionIDs.intersection(reconfiguredHeaderSectionIDs).isEmpty {
            tableView.beginUpdates()
            tableView.endUpdates()
        }

        let sectionIndexes = sectionIndexes(for: changedSectionIDs, in: snapshot)
        if !sectionIndexes.isEmpty {
            tableView.reloadSections(sectionIndexes, with: .automatic)
            return
        }

        if !reconfiguredHeaderSectionIDs.isEmpty {
            return
        }

        if forceReload,
           tableView.numberOfSections != max(snapshot.count, 1) {
            tableView.reloadData()
        }
    }

    private func reloadDisabledSectionsTable(forceReload: Bool = false,
                                            debounced: Bool = false,
                                            preferredSectionIDs: Set<String> = []) {
        disabledSectionsNeedsForceReload = disabledSectionsNeedsForceReload || forceReload
        disabledSectionsPendingSectionIDs.formUnion(preferredSectionIDs)
        disabledSectionsReloadWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }
            let shouldForceReload = self.disabledSectionsNeedsForceReload
            self.disabledSectionsNeedsForceReload = false
            self.disabledSectionsReloadWorkItem = nil
            self.applyDisabledSectionsSnapshotIfNeeded(forceReload: shouldForceReload)
        }
        disabledSectionsReloadWorkItem = workItem

        if debounced {
            DispatchQueue.main.asyncAfter(deadline: .now() + disabledSectionsReloadDebounceInterval, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    private func cancelDisabledSectionsReload() {
        disabledSectionsReloadWorkItem?.cancel()
        disabledSectionsReloadWorkItem = nil
        disabledSectionsNeedsForceReload = false
        disabledSectionsPendingSectionIDs.removeAll()
    }

    private func startObservingDisabledSourceChanges() {
        guard disabledSourcesObserver == nil else {
            return
        }
        disabledSourcesObserver = NotificationCenter.default.addObserver(forName: RepoManager.repoStateDidChangeNotification,
                                                                        object: nil,
                                                                        queue: .main) { [weak self] _ in
            guard let self = self,
                  self.isViewLoaded,
                  self.view.window != nil else {
                return
            }
            self.reloadDisabledSectionsTable(debounced: true)
        }
    }

    private func stopObservingDisabledSourceChanges() {
        cancelDisabledSectionsReload()
        guard let observer = disabledSourcesObserver else {
            return
        }
        NotificationCenter.default.removeObserver(observer)
        disabledSourcesObserver = nil
    }

    private func section(at index: Int) -> DisabledSourceSection? {
        disabledSectionsSnapshot.indices.contains(index) ? disabledSectionsSnapshot[index] : nil
    }

    private func section(withID id: String) -> DisabledSourceSection? {
        disabledSectionsSnapshot.first { $0.id == id }
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
        guard let section = section(at: indexPath.section),
              section.repos.indices.contains(indexPath.row) else {
            return nil
        }
        return section.repos[indexPath.row]
    }

    private func repos(inSectionID sectionID: String) -> [Repo] {
        section(withID: sectionID)?.repos ?? []
    }

    private func removableRepos(inSectionID sectionID: String) -> [Repo] {
        repos(inSectionID: sectionID).filter(canRemove)
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

    private func enableSection(_ sectionID: String) {
        guard !DownloadManager.shared.queueRunning else {
            TabBarController.singleton?.presentPopupController()
            return
        }
        let repos = repos(inSectionID: sectionID)
        guard !repos.isEmpty else {
            return
        }
        RepoManager.shared.enableRepos(repos)
        reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: [sectionID])
    }

    private func removeSection(_ sectionID: String) {
        let removableRepos = removableRepos(inSectionID: sectionID)
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
        reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: [sectionID])
    }

    private func refreshSection(_ sectionID: String) {
        let repos = repos(inSectionID: sectionID)
        guard !repos.isEmpty, activeRefreshSectionID == nil else {
            return
        }

        var previousSuccessByRepo = [String: Date?]()
        for repo in repos {
            previousSuccessByRepo[repo.refreshStateKey] = RepoManager.shared.refreshState(for: repo).lastSuccessAt
        }

        activeRefreshSectionID = sectionID
        reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: [sectionID])

        RepoManager.shared.update(force: false,
                                  forceReload: true,
                                  isBackground: false,
                                  selectionMode: .explicit,
                                  repos: repos) { didFindErrors, errorOutput in
            var reposToEnable = [Repo]()
            for repo in repos {
                let previousSuccessAt = previousSuccessByRepo[repo.refreshStateKey] ?? nil
                if self.refreshSucceeded(repo: repo, previousSuccessAt: previousSuccessAt),
                   RepoManager.shared.isRepoDisabled(repo) {
                    reposToEnable.append(repo)
                }
            }

            if !reposToEnable.isEmpty {
                RepoManager.shared.enableRepos(reposToEnable)
            }
            self.activeRefreshSectionID = nil
            self.reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: [sectionID])

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
        tableView.register(DisabledSourcesSectionHeaderView.self,
                           forHeaderFooterViewReuseIdentifier: DisabledSourcesSectionHeaderView.reuseIdentifier)
        disabledSectionsSnapshot = buildDisabledSectionsSnapshot()
        renderedActiveRefreshSectionID = activeRefreshSectionID
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startObservingDisabledSourceChanges()
        reloadDisabledSectionsTable(forceReload: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopObservingDisabledSourceChanges()
    }

    deinit {
        cancelDisabledSectionsReload()
        stopObservingDisabledSourceChanges()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        max(disabledSectionsSnapshot.count, 1)
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !disabledSectionsSnapshot.isEmpty else {
            return nil
        }
        guard let sectionInfo = self.section(at: section) else {
            return super.tableView(tableView, viewForHeaderInSection: section)
        }

        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: DisabledSourcesSectionHeaderView.reuseIdentifier) as? DisabledSourcesSectionHeaderView ?? DisabledSourcesSectionHeaderView(reuseIdentifier: DisabledSourcesSectionHeaderView.reuseIdentifier)
        configureHeaderView(headerView, section: sectionInfo)
        return headerView
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        disabledSectionsSnapshot.isEmpty ? CGFloat.leastNonzeroMagnitude : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        disabledSectionsSnapshot.isEmpty ? 0 : 112
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !disabledSectionsSnapshot.isEmpty else {
            return 1
        }
        return self.section(at: section)?.repos.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if disabledSectionsSnapshot.isEmpty {
            let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "DisabledSourcesEmptyCell")
            cell.textLabel?.text = String(localizationKey: "Disabled_Sources_Empty")
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }

        guard let repo = repo(at: indexPath) else {
            let cell = self.reusableCell(withStyle: .default, reuseIdentifier: "DisabledSourcesFallbackCell")
            cell.textLabel?.text = String(localizationKey: "Disabled_Sources_Empty")
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
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
            let sectionID = self.section(at: indexPath.section)?.id
            self.reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: Set(sectionID.map { [$0] } ?? []))
        })
        if self.canRemove(repo) {
            alert.addAction(UIAlertAction(title: String(localizationKey: "Remove"), style: .destructive) { _ in
                guard !DownloadManager.shared.queueRunning else {
                    TabBarController.singleton?.presentPopupController()
                    return
                }
                RepoManager.shared.remove(repo: repo)
                let sectionID = self.section(at: indexPath.section)?.id
                self.reloadDisabledSectionsTable(forceReload: true, preferredSectionIDs: Set(sectionID.map { [$0] } ?? []))
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

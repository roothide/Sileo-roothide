//
//  DpkgWrapper.swift
//  Anemone
//
//  Created by CoolStar on 6/23/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation

enum pkgwant: String {
    case unknown = "unknown"
    case install = "install"
    case hold = "hold"
    case deinstall = "deinstall"
    case purge = "purge"
    case sentinel
}

enum pkgeflag: String {
    case ok = "ok"
    case reinstreq = "reinstreq"
}

enum pkgstatus: String {
    case notinstalled = "not-installed"
    case configfiles = "config-files"
    case halfinstalled = "half-installed"
    case unpacked = "unpacked" /*You might want to run 'apt --fix-broken install' to correct these.
                                The following packages have unmet dependencies:
                                 rootless-compat : Depends: com.roothide.patchloader (>= 0.0.4) but it is not going to be installed
                                E: Unmet dependencies. Try 'apt --fix-broken install' with no packages (or specify a solution).*/
    case halfconfigured = "half-configured"
    case triggersawaited = "triggers-awaited"
    case triggerspending = "triggers-pending"
    case installed = "installed"
}

enum pkgpriority: String {
    case required = "required"
    case important = "important"
    case standard = "standard"
    case optional = "optional"
    case extra = "extra"
    case other
    case unknown = "unknown"
    case unset
}

class DpkgWrapper {

    public class func dpkgInterrupted() -> Bool {
        let updatesDir = CommandPath.dpkgDir.appendingPathComponent("updates/")
        var interrupted = false
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: updatesDir.absoluteURL.path) else {
            return interrupted
        }
        for file in contents {
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: file)) {
                interrupted = true
            }
        }
        return interrupted
    }
 
    public static var architecture: DPKGArchitecture = {
        #if arch(x86_64) && !targetEnvironment(simulator)
        let defaultArchitectures: DPKGArchitecture = DPKGArchitecture(primary: .intel, foreign: [])
        #elseif arch(arm64) && os(macOS) && !targetEnvironment(simulator)
        let defaultArchitectures: DPKGArchitecture = DPKGArchitecture(primary: .applesilicon, foreign: [])
        #else
        let defaultArchitectures: DPKGArchitecture
        if Bootstrap.roothide {
            defaultArchitectures = DPKGArchitecture(primary: .roothide, foreign: [.rootless])
        } else if Bootstrap.rootless {
                defaultArchitectures = DPKGArchitecture(primary: .rootless, foreign: [])
        } else {
            defaultArchitectures = DPKGArchitecture(primary: .rootful, foreign: [])
        }
        NSLog("SileoLog: defaultArch=\(defaultArchitectures.primary.rawValue)")
        #endif
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        print("Default Archs: \(defaultArchitectures)")
        return defaultArchitectures
        #else
        
        //acc
        return defaultArchitectures
        
        let (localStatus, localArchs, _) = spawn(command: CommandPath.dpkg, args: ["dpkg", "--print-architecture"])
        guard localStatus == 0 else {
            return defaultArchitectures
        }
        let primary = localArchs.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "").lowercased()
        guard let arch = DPKGArchitecture.Architecture(rawValue: primary) else {
            return defaultArchitectures
        }
        let (foreignStatus, foreignArchs, _) = spawn(command: CommandPath.dpkg, args: ["dpkg", "--print-foreign-architectures"])
        guard foreignStatus == 0 else {
            return defaultArchitectures
        }
        let foreignSet = foreignArchs.replacingOccurrences(of: " ", with: "").lowercased().components(separatedBy: "\n")
        var _foreign = Set<DPKGArchitecture.Architecture>()
        for component in foreignSet {
            if let arch = DPKGArchitecture.Architecture(rawValue: component) {
                _foreign.insert(arch)
            }
        }
        if Bootstrap.roothide {
            _foreign.insert(DPKGArchitecture.Architecture.rootless)
        }
        return DPKGArchitecture(primary: arch, foreign: _foreign)
        #endif
    }()
    
    public class func isVersion(_ version: String, greaterThan: String) -> Bool {
        compareVersion(version, Int32(version.count + 1), greaterThan, Int32(greaterThan.count + 1)) > 0
    }
    
    public class func getValues(statusField: String?, wantInfo : inout pkgwant, eFlag : inout pkgeflag, pkgStatus : inout pkgstatus) -> Bool {
        guard let statusParts = statusField?.components(separatedBy: CharacterSet(charactersIn: " ")) else {
            return false
        }
        if statusParts.count < 3 {
            return false
        }
        wantInfo = .unknown
        if let wantValue = pkgwant(rawValue: statusParts[0]) {
            wantInfo = wantValue
        }
        if let eflagValue = pkgeflag(rawValue: statusParts[1]) {
            eFlag = eflagValue
        }
        if let statusValue = pkgstatus(rawValue: statusParts[2]) {
            pkgStatus = statusValue
        }
        return true
    }
    
    public class func ignoreUpdates(_ ignoreUpdates: Bool, package: String) throws {
        let ignoreCommand = ignoreUpdates ? "hold" : "unhold"
        let command = [CommandPath.aptmark, "-oDir::State::lists=", "\(ignoreCommand)", "\(package)"]
        let (status,stdout,stderr) = spawnAsRoot(args: command)
        if status != 0 {
            throw NSError(domain: "Sileo.Apt", code: 0, userInfo: ["Description": "apt-mark return \(status)\n\(stdout)\n\(stderr)"])
        }
    }
    
    public class func rawFields(packageURL: URL) throws -> String {
        guard packageURL.isFileURL else {
            throw NSError(domain: "Sileo.Dpkg", code: 3, userInfo: ["Description": "URL provided not a file url!"])
        }
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        return """
        Package: bash
        Version: 4.4.18
        Architecture: iphoneos-arm
        Maintainer: CoolStar <coolstarorganization@gmail.com>
        Depends: grep, ncurses (>=6.1), sed, cy+cpu.arm64
        Section: Terminal_Support
        Priority: required
        Homepage: http://www.gnu.org/software/bash/
        Description: the best shell ever written by Brian Fox
        Name: Bourne-Again SHell
        """
        #else
        //the permission of control in some packages may be 000 so here we need run as root
        let (_, outputString, _) = spawn(command: CommandPath.dpkgdeb, args: ["dpkg-deb", "--field", rootfs("\(packageURL.path)")], root: true)
        return outputString
        #endif
    }
}

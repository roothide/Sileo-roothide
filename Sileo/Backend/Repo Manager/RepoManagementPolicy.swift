//
//  RepoManagementPolicy.swift
//  Sileo
//
//  Created by Codex on 2026/05/05.
//

import Foundation

enum RepoSourceExportMode: String, CaseIterable {
    case all
    case activeOnly
}

struct RepoSourceExportEntry: Equatable {
    let aptSource: String?
    let isDisabled: Bool
}

enum RepoSourceExportFormatter {
    static func exportText(entries: [RepoSourceExportEntry], mode: RepoSourceExportMode) -> String {
        entries
            .filter { mode == .all || !$0.isDisabled }
            .compactMap(\.aptSource)
            .joined(separator: "\n")
    }
}

enum HTTP522Treatment: String, CaseIterable {
    case websiteError
    case timeout
}

enum RepoRefreshFailureClassification: Equatable {
    case other
    case timeout
    case httpStatus(Int)
}

enum RepoRefreshFailureClassifier {
    static func classify(status: Int, isTimeoutError: Bool, http522Treatment: HTTP522Treatment) -> RepoRefreshFailureClassification {
        if status == 522 {
            switch http522Treatment {
            case .websiteError:
                return .httpStatus(status)
            case .timeout:
                return .timeout
            }
        }

        if isTimeoutError {
            return .timeout
        }

        if status > 0 {
            return .httpStatus(status)
        }

        return .other
    }
}

//
//  DeepseekModels.swift
//  boringNotch
//
//  Created on 2026-06-21.
//

import Foundation

struct DeepseekBalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceInfo: Codable, Identifiable {
    var id: String { currency }
    let currency: String
    let totalBalance: String
    let toppedUpBalance: String
    let grantedBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case toppedUpBalance = "topped_up_balance"
        case grantedBalance = "granted_balance"
    }
}

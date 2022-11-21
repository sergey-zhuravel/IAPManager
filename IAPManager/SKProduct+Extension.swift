//
//  SKProduct+Extension.swift
//  IAPManager
//
//  Created by Sergey Zhuravel on 1/12/22.
//

import UIKit
import StoreKit

extension SKProduct {
    var localizedCurrencyPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)!
    }

    var title: String? {
        switch productIdentifier {
        case IAPManager.shared.PREMIUM_MONTH_PRODUCT_ID:
            return "Monthly"
        case IAPManager.shared.PREMIUM_YEAR_PRODUCT_ID:
            return "7 days free then"
        default:
            return nil
        }
    }
}

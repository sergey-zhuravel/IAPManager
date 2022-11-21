//
//  IAPPersistence.swift
//  IAPManager
//
//  Created by Sergey Zhuravel on 11/8/22.
//

import Foundation

protocol IAPPersistenceProtocol {
    static func savePurchasedState(for productId: ProductId, purchased: Bool)
    static func savePurchasedState(for productIds: Set<ProductId>, purchased: Bool)
    static func loadPurchasedState(for productId: ProductId) -> Bool
    static func loadPurchasedProductIds(for productIds: Set<ProductId>) -> Set<ProductId>
}

public struct IAPPersistence: IAPPersistenceProtocol {
    
    public static func savePurchasedState(for productId: ProductId, purchased: Bool = true) {
        UserDefaults.standard.set(purchased, forKey: productId)
    }
    
    public static func savePurchasedState(for productIds: Set<ProductId>, purchased: Bool = true) {
        productIds.forEach { productId in UserDefaults.standard.set(purchased, forKey: productId) }
    }
    
    public static func loadPurchasedState(for productId: ProductId) -> Bool {
        return UserDefaults.standard.bool(forKey: productId)
    }
    
    public static func loadPurchasedProductIds(for productIds: Set<ProductId>) -> Set<ProductId> {
        var purchasedProductIds = Set<ProductId>()
        productIds.forEach { productId in
            let purchased = UserDefaults.standard.bool(forKey: productId)
            if purchased {
                purchasedProductIds.insert(productId)
                print("Loaded purchased product: \(productId)")
            }
        }
        
        return purchasedProductIds
    }
    
    public static func resetPurchasedProductIds(from oldProductIds: Set<ProductId>, to productIds: Set<ProductId>, purchased: Bool = true) {
        oldProductIds.forEach { pid in UserDefaults.standard.removeObject(forKey: pid) }
        savePurchasedState(for: productIds, purchased: purchased)
    }
}


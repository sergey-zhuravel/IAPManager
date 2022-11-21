//
//  IAPManager.swift
//  IAPManager
//
//  Created by Sergey Zhuravel on 12/30/21.
//

import UIKit
import StoreKit

enum IAPManagerAlertType {
    case disabled
    case restored
    case purchased
    case failed
    
    func message() -> String {
        switch self {
        case .disabled: return "Purchases are disabled in your device!"
        case .restored: return "You've successfully restored your purchase!"
        case .purchased: return "You've successfully bought this purchase!"
        case .failed: return "Could not complete purchase process.\nPlease try again."
        }
    }
}

private let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

var appConfiguration: AppConfiguration {
  if isDebug {
    return .Debug
  } else if isTestFlight {
    return .TestFlight
  } else {
    return .AppStore
  }
}

enum AppConfiguration: String {
  case Debug
  case TestFlight
  case AppStore
}

var isDebug: Bool {
  #if DEBUG
  return true
  #else
  return false
  #endif
}

public typealias ProductId = String

class IAPManager: NSObject {
    static let shared = IAPManager()
    
    let PREMIUM_MONTH_PRODUCT_ID = "com.testapp.month"
    let PREMIUM_YEAR_PRODUCT_ID = "com.testapp.year"
    
    fileprivate var productsRequest = SKProductsRequest()
    fileprivate var iapProducts = [SKProduct]()
    fileprivate var pendingFetchProduct: String!
    var fetchAvailableProductsBlock : (([SKProduct]) -> Void)? = nil
    var purchaseStatusBlock: ((IAPManagerAlertType) -> Void)?
    private var receipt: IAPReceipt!
    
    public var purchasedProductIdentifiers = Set<ProductId>()
    
    func initialize() {
        fetchAvailableProducts()
    }
    
    // MARK: - FETCH AVAILABLE IAP PRODUCTS
    private func fetchAvailableProducts(){
        productsRequest.cancel()
        // Put here your IAP Products ID's
        let productIdentifiers = NSSet(objects: PREMIUM_MONTH_PRODUCT_ID, PREMIUM_YEAR_PRODUCT_ID)
        
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers as! Set<String>)
        productsRequest.delegate = self
        productsRequest.start()
    }
    
    // MARK: - MAKE PURCHASE OF A PRODUCT
    func canMakePurchases() -> Bool { return SKPaymentQueue.canMakePayments() }
    
    func purchaseMyProduct(productIdentifier: String) {
        if iapProducts.isEmpty {
            pendingFetchProduct = productIdentifier
            fetchAvailableProducts()
            return
        }
        
        if canMakePurchases() {
            for product in iapProducts {
                if product.productIdentifier == productIdentifier {
                    let payment = SKPayment(product: product)
                    SKPaymentQueue.default().add(self)
                    SKPaymentQueue.default().add(payment)
                }
            }
        } else {
            purchaseStatusBlock?(.disabled)
        }
    }
    
    // MARK: - RESTORE PURCHASE
    func restorePurchase(){
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

extension IAPManager: SKProductsRequestDelegate {
    // MARK: - REQUEST IAP PRODUCTS
    func productsRequest (_ request:SKProductsRequest, didReceive response:SKProductsResponse) {
        if response.products.count > 0 {
            iapProducts = response.products
            fetchAvailableProductsBlock?(response.products)
            
            if let product = pendingFetchProduct {
                purchaseMyProduct(productIdentifier: product)
            }
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Error load products", error)
    }
}

extension IAPManager: SKPaymentTransactionObserver {
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        purchaseStatusBlock?(.restored)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        purchaseStatusBlock?(.failed)
    }
    
    // MARK: - IAP PAYMENT QUEUE
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction: AnyObject in transactions {
            if let trans = transaction as? SKPaymentTransaction {
                switch trans.transactionState {
                case .purchased:
                    if let transaction = transaction as? SKPaymentTransaction {
                        purchaseStatusBlock?(.purchased)
                        SKPaymentQueue.default().finishTransaction(transaction)
                        
                        if IAPConstants.isLocalValidateReceipt {
                            let _ = processReceipt()
                        } else {
                            receiptAppStoreValidation()
                        }
                    }
                case .failed:
                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
                    purchaseStatusBlock?(.failed)
                case .restored:
                    if let transaction = transaction as? SKPaymentTransaction {
                        SKPaymentQueue.default().finishTransaction(transaction)
                    }
                default: break
                }
            }
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        if canMakePurchases() {
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(self)
            SKPaymentQueue.default().add(payment)
            
            return true
        } else {
            return false
        }
    }
}

extension IAPManager {
    
    public func processReceipt() -> Bool {
        print("receiptValidationStarted")
        
        receipt = IAPReceipt()
        
        guard receipt.isReachable,
              receipt.load(),
              receipt.validateSigning(),
              receipt.read(),
              receipt.validate() else {
            
            print("receiptProcessingFailure")
            return false
        }
        
        createValidatedPurchasedProductIds(receipt: receipt)
        print("receiptProcessingSuccess")
        return true
    }
    
    
    private func createValidatedPurchasedProductIds(receipt: IAPReceipt) {
        if purchasedProductIdentifiers == receipt.validatedPurchasedProductIdentifiers {
            print("purchasedProductsValidatedAgainstReceipt")
            return
        }
        
        IAPPersistence.resetPurchasedProductIds(from: purchasedProductIdentifiers, to: receipt.validatedPurchasedProductIdentifiers)
        purchasedProductIdentifiers = receipt.validatedPurchasedProductIdentifiers
        print("purchasedProductsValidatedAgainstReceipt")
    }
}

extension IAPManager {
    
    var validationURLString: String {
      if appConfiguration != .AppStore { return "https://sandbox.itunes.apple.com/verifyReceipt" }
      return "https://buy.itunes.apple.com/verifyReceipt"
    }
    
    // Status code returned by remote server
    public enum ReceiptStatus: Int {
        // Not decodable status
        case unknown = -2
        // No status returned
        case none = -1
        // valid statu
        case valid = 0
        // The App Store could not read the JSON object you provided.
        case jsonNotReadable = 21000
        // The data in the receipt-data property was malformed or missing.
        case malformedOrMissingData = 21002
        // The receipt could not be authenticated.
        case receiptCouldNotBeAuthenticated = 21003
        // The shared secret you provided does not match the shared secret on file for your account.
        case secretNotMatching = 21004
        // The receipt server is not currently available.
        case receiptServerUnavailable = 21005
        // This receipt is valid but the subscription has expired. When this status code is returned to your server, the receipt data is also decoded and returned as part of the response.
        case subscriptionExpired = 21006
        //  This receipt is from the test environment, but it was sent to the production environment for verification. Send it to the test environment instead.
        case testReceipt = 21007
        // This receipt is from the production environment, but it was sent to the test environment for verification. Send it to the production environment instead.
        case productionEnvironment = 21008

        var isValid: Bool { return self == .valid}
    }
    
    func receiptAppStoreValidation() {
        
        let SUBSCRIPTION_SECRET = "YOUR_SHARED_SECRET"
        guard let receiptPath = Bundle.main.appStoreReceiptURL?.path else { return }
        if FileManager.default.fileExists(atPath: receiptPath) {
            var receiptData: NSData?
            do {
                receiptData = try NSData(contentsOf: Bundle.main.appStoreReceiptURL!, options: NSData.ReadingOptions.alwaysMapped)
            } catch {
                print("ERROR receiptValidation: \(error.localizedDescription)")
            }
            let base64encodedReceipt = receiptData?.base64EncodedString(options: NSData.Base64EncodingOptions.endLineWithCarriageReturn)
            let requestDictionary = ["receipt-data": base64encodedReceipt!, "password": SUBSCRIPTION_SECRET]
            
            guard JSONSerialization.isValidJSONObject(requestDictionary) else { print("requestDictionary is not valid JSON"); return }
            do {
                let requestData = try JSONSerialization.data(withJSONObject: requestDictionary)
                guard let validationURL = URL(string: validationURLString) else { print("the validation url could not be created, unlikely error"); return }
                let session = URLSession(configuration: URLSessionConfiguration.default)
                var request = URLRequest(url: validationURL)
                request.httpMethod = "POST"
                request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
                let task = session.uploadTask(with: request, from: requestData) { data, _, error in
                    if let data = data, error == nil {
                        do {
                            let appReceiptJSON = try JSONSerialization.jsonObject(with: data) as! NSDictionary
                            
                            if appReceiptJSON["status"] != nil {
                                if let status = appReceiptJSON["status"] as? Int {
                                    let receiptStatus = ReceiptStatus(rawValue: status) ?? ReceiptStatus.unknown
                                    
                                    if receiptStatus.isValid {
                                        var latestReceipt = ""
                                        if appReceiptJSON["latest_receipt"] != nil {
                                            latestReceipt = appReceiptJSON["latest_receipt"] as! String
                                            //here you can parse the receipt and determine if there is an active subscription or not
                                            
                                        }
                                    } else {
                                        print("receipt not valid")
                                    }
                                }
                            }
                        } catch let error as NSError {
                            print("json serialization failed with error: \(error.localizedDescription)")
                        }
                    } else {
                        print("the upload task returned an error: \(String(describing: error))")
                    }
                }
                task.resume()
            } catch let error as NSError {
                print("json serialization failed with error: \(error)")
            }
        }
    }
}

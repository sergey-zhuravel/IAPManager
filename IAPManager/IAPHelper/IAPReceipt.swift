//
//  IAPReceipt.swift
//  IAPManager
//
//  Created by Sergey Zhuravel on 11/7/22.
//

import UIKit

public class IAPReceipt {
    
    public var validatedPurchasedProductIdentifiers = Set<ProductId>()

    public var isReachable: Bool {
        guard let receiptUrl = Bundle.main.appStoreReceiptURL else {
            print("receiptBadUrl")
            return false
        }
        
        print("Receipt reachable at \(receiptUrl)")
        guard let _ = try? receiptUrl.checkResourceIsReachable() else {
            print("receiptMissing")
            return false
        }
        
        return true
    }
    
    public var isValid = false
    private var inAppReceipts: [IAPReceiptProductInfo] = []
    private var receiptData: UnsafeMutablePointer<PKCS7>?
    private var bundleIdString: String?
    private var bundleVersionString: String?
    private var bundleIdData: Data?
    private var hashData: Data?
    private var opaqueData: Data?
    private var expirationDate: Date?
    private var receiptCreationDate: Date?
    private var originalAppVersion: String?
        
    internal func getDeviceIdentifier() -> Data {
        let device = UIDevice.current
        var uuid = device.identifierForVendor!.uuid
        let addr = withUnsafePointer(to: &uuid) { (p) -> UnsafeRawPointer in
            UnsafeRawPointer(p)
        }
        let data = Data(bytes: addr, count: 16)
        return data
    }
    
    internal func computeHash() -> Data {
        let identifierData = getDeviceIdentifier()
        var ctx = SHA_CTX()
        SHA1_Init(&ctx)
        
        let identifierBytes: [UInt8] = .init(identifierData)
        SHA1_Update(&ctx, identifierBytes, identifierData.count)
        
        let opaqueBytes: [UInt8] = .init(opaqueData!)
        SHA1_Update(&ctx, opaqueBytes, opaqueData!.count)
        
        let bundleBytes: [UInt8] = .init(bundleIdData!)
        SHA1_Update(&ctx, bundleBytes, bundleIdData!.count)
        
        var hash: [UInt8] = .init(repeating: 0, count: 20)
        SHA1_Final(&hash, &ctx)
        return Data(bytes: hash, count: 20)
    }
}

extension IAPReceipt {

    public func validateSigning() -> Bool {

        guard receiptData != nil else {
            print("receiptValidateSigningFailure")
            return false
        }
        
        guard let rootCertUrl = Bundle.main.url(forResource: IAPConstants.Certificate(), withExtension: IAPConstants.CertificateExt()),
              let rootCertData = try? Data(contentsOf: rootCertUrl) else {
            print("receiptValidateSigningFailure")
            return false
        }
        
        let rootCertBio = BIO_new(BIO_s_mem())
        let rootCertBytes: [UInt8] = .init(rootCertData)
        BIO_write(rootCertBio, rootCertBytes, Int32(rootCertData.count))
        let rootCertX509 = d2i_X509_bio(rootCertBio, nil)
        BIO_free(rootCertBio)
        
        let store = X509_STORE_new()
        X509_STORE_add_cert(store, rootCertX509)
        
        OPENSSL_init_crypto(UInt64(OPENSSL_INIT_ADD_ALL_DIGESTS), nil)
        
        // If PKCS7_NOCHAIN is set the signer's certificates are not chain verified.
        // This is required when using the local testing StoreKitTestCertificate.cer certificate.
        // See https://developer.apple.com/videos/play/wwdc2020/10659/ at the 16:30 mark.
        #if DEBUG
        let verificationResult = PKCS7_verify(receiptData, nil, store, nil, nil, PKCS7_NOCHAIN)
        #else
        let verificationResult = PKCS7_verify(receiptData, nil, store, nil, nil, nil)
        #endif
        
        guard verificationResult == 1  else {
            print("receiptValidateSigningFailure")
            return false
        }
        
        print("receiptValidateSigningSuccess")
        return true
    }
}

extension IAPReceipt {
    
    public func validate() -> Bool {
        guard let idString = bundleIdString,
              let version = bundleVersionString,
              let _ = opaqueData,
              let hash = hashData else {
            
            print("receiptValidationFailure")
            return false
        }
        
        guard let appBundleId = Bundle.main.bundleIdentifier else {
            print("receiptValidationFailure")
            return false
        }
        
        guard idString == appBundleId else {
            print("receiptValidationFailure")
            return false
        }
        
        guard let appVersionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            print("receiptValidationFailure")
            return false
        }
        
        guard version == appVersionString else {
            print("receiptValidationFailure")
            return false
        }
        
        guard hash == computeHash() else {
            print("receiptValidationFailure")
            return false
        }
        
        if let expirationDate = expirationDate {
            if expirationDate < Date() {
                print("receiptValidationFailure")
                return false
            }
        }
        
        isValid = true
        print("receiptValidationSuccess")
        return true
    }
    
    public func compareProductIds(fallbackPids: Set<ProductId>) -> Bool { fallbackPids == validatedPurchasedProductIdentifiers }
}

extension IAPReceipt {
    
    public func read() -> Bool {
        
        let receiptSign = receiptData?.pointee.d.sign
        let octets = receiptSign?.pointee.contents.pointee.d.data
        var pointer = UnsafePointer(octets?.pointee.data)
        let end = pointer!.advanced(by: Int(octets!.pointee.length))
        
        var type: Int32 = 0
        var xclass: Int32 = 0
        var length: Int = 0
        
        ASN1_get_object(&pointer, &length, &type, &xclass, pointer!.distance(to: end))
        guard type == V_ASN1_SET else {
            print("receiptReadFailure")
            return false
        }
        
        while pointer! < end {
            ASN1_get_object(&pointer, &length, &type, &xclass, pointer!.distance(to: end))
            guard type == V_ASN1_SEQUENCE else {
                print("receiptReadFailure")
                return false
            }
            
            guard let attributeType = IAPOpenSSL.asn1Int(p: &pointer, expectedLength: length) else {
                print("receiptReadFailure")
                return false
            }
            
            guard let _ = IAPOpenSSL.asn1Int(p: &pointer, expectedLength: pointer!.distance(to: end)) else {
                print("receiptReadFailure")
                return false
            }
            
            ASN1_get_object(&pointer, &length, &type, &xclass, pointer!.distance(to: end))
            guard type == V_ASN1_OCTET_STRING else {
                print("receiptReadFailure")
                return false
            }
            
            var p = pointer
            switch IAPOpenSSLAttributeType(rawValue: attributeType) {
                
            case .BudleVersion: bundleVersionString         = IAPOpenSSL.asn1String(    p: &p, expectedLength: length)
            case .ReceiptCreationDate: receiptCreationDate  = IAPOpenSSL.asn1Date(      p: &p, expectedLength: length)
            case .OriginalAppVersion: originalAppVersion    = IAPOpenSSL.asn1String(    p: &p, expectedLength: length)
            case .ExpirationDate: expirationDate            = IAPOpenSSL.asn1Date(      p: &p, expectedLength: length)
            case .OpaqueValue: opaqueData                   = IAPOpenSSL.asn1Data(      p: p!, expectedLength: length)
            case .ComputedGuid: hashData                    = IAPOpenSSL.asn1Data(      p: p!, expectedLength: length)
                
            case .BundleIdentifier:
                bundleIdString                              = IAPOpenSSL.asn1String(    p: &pointer, expectedLength: length)
                bundleIdData                                = IAPOpenSSL.asn1Data(      p: pointer!, expectedLength: length)
                
            case .IAPReceipt:
                var iapStartPtr = pointer
                let receiptProductInfo = IAPReceiptProductInfo(with: &iapStartPtr, payloadLength: length)
                if let rpi = receiptProductInfo {
                    inAppReceipts.append(rpi)
                    if let pid = rpi.productIdentifier { validatedPurchasedProductIdentifiers.insert(pid) }
                }
                
            default: break
            }
            
            pointer = pointer!.advanced(by: length)
        }
        
        print("receiptReadSuccess")
        return true
    }
}

extension IAPReceipt {
    
    public func load() -> Bool {
        
        guard let receiptUrl = Bundle.main.appStoreReceiptURL else {
            print("receiptLoadFailure")
            return false
        }
        
        guard let data = try? Data(contentsOf: receiptUrl) else {
            print("receiptLoadFailure")
            return false
        }
        
        let receiptBIO = BIO_new(BIO_s_mem())
        let receiptBytes: [UInt8] = .init(data)
        BIO_write(receiptBIO, receiptBytes, Int32(data.count))
        let receiptPKCS7 = d2i_PKCS7_bio(receiptBIO, nil)
        BIO_free(receiptBIO)

        guard receiptPKCS7 != nil else {
            print("receiptLoadFailure")
            return false
        }
        
        guard pkcs7IsSigned(pkcs7: receiptPKCS7!) else {
            print("receiptLoadFailure")
            return false
        }
        
        guard pkcs7IsData(pkcs7: receiptPKCS7!) else {
            print("receiptLoadFailure")
            return false
        }
        
        receiptData = receiptPKCS7
        print("receiptLoadSuccess")
        return true
    }
    
    func pkcs7IsSigned(pkcs7: UnsafeMutablePointer<PKCS7>) -> Bool {
        OBJ_obj2nid(pkcs7.pointee.type) == NID_pkcs7_signed
    }
    
    func pkcs7IsData(pkcs7: UnsafeMutablePointer<PKCS7>) -> Bool {
        OBJ_obj2nid(pkcs7.pointee.d.sign.pointee.contents.pointee.type) == NID_pkcs7_data
    }
}

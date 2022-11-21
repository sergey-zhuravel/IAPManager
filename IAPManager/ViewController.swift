//
//  ViewController.swift
//  IAPManager
//
//  Created by Sergey Zhuravel on 12/30/21.
//

import UIKit
import StoreKit

class ViewController: UIViewController {
    
    @IBOutlet weak var yearButton: UIButton!
    @IBOutlet weak var monthButton: UIButton!
    @IBOutlet weak var restoreButton: UIButton!

    var actIndicator: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        
        IAPManager.shared.purchaseStatusBlock = { [weak self] (type) in
            self?.showAlert(title: type.message())
            self?.actIndicator.stopAnimating()
            self?.purchaseButtonsEnabled(isOn: true)
        }
    }
    
    // MARK: - UI
    
    func setupUI() {
        
        self.actIndicator = UIActivityIndicatorView.init(style: .medium)
        self.actIndicator.center = self.view.center
        self.view.addSubview(self.actIndicator)
        
        IAPManager.shared.initialize()
        IAPManager.shared.fetchAvailableProductsBlock = { (productsArray) in
            DispatchQueue.main.async {
                self.updateUI(productsArray:productsArray)
            }
        }
    }
    
    func updateUI(productsArray:[SKProduct]) {
        monthButton.setTitle("\(productsArray[0].title ?? productsArray[0].productIdentifier) \(productsArray[0].localizedCurrencyPrice)", for: .normal)
        yearButton.setTitle("\(productsArray[1].title ?? productsArray[1].productIdentifier) \(productsArray[1].localizedCurrencyPrice)/year", for: .normal)
    }
    
    // MARK: - ACTIONS
    
    @IBAction func tappedYearButton(_ sender: UIButton) {
        actIndicator.startAnimating()
        purchaseButtonsEnabled(isOn: false)
        IAPManager.shared.purchaseMyProduct(productIdentifier: IAPManager().PREMIUM_YEAR_PRODUCT_ID)
    }
    
    @IBAction func tappedMonthButton(_ sender: UIButton) {
        actIndicator.startAnimating()
        purchaseButtonsEnabled(isOn: false)
        IAPManager.shared.purchaseMyProduct(productIdentifier: IAPManager().PREMIUM_MONTH_PRODUCT_ID)
    }
    
    @IBAction func tappedRestorePurchaseButton(_ sender: UIButton) {
        actIndicator.startAnimating()
        purchaseButtonsEnabled(isOn: false)
        IAPManager.shared.restorePurchase()
    }
    
    private func purchaseButtonsEnabled(isOn:Bool) {
        yearButton.isEnabled = isOn
        monthButton.isEnabled = isOn
        restoreButton.isEnabled = isOn
    }
    
    // MARK: - ALERT
    
    func showAlert(title: String) {
      let alert = UIAlertController(title: title, message: nil, preferredStyle: UIAlertController.Style.alert)
      alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { _ in
      }))
      present(alert, animated: true, completion: nil)
    }
}


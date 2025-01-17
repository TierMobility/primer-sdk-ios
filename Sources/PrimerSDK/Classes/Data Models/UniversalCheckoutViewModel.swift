//
//  VaultCheckoutViewModel.swift
//  PrimerSDK
//
//  Created by Evangelos Pittas on 6/8/21.
//

#if canImport(UIKit)

import Foundation

internal protocol UniversalCheckoutViewModelProtocol {
    var paymentMethods: [PrimerPaymentMethodTokenData] { get }
    var selectedPaymentMethod: PrimerPaymentMethodTokenData? { get }
    var amountStr: String? { get }
}

internal class UniversalCheckoutViewModel: UniversalCheckoutViewModelProtocol {

    var amountStr: String? {
        if (PrimerInternal.shared.intent ?? .vault) == .vault { return nil }
        guard let amount = AppState.current.amount else { return nil }
        guard let currency = AppState.current.currency else { return nil }
        return amount.toCurrencyString(currency: currency)
    }

    var paymentMethods: [PrimerPaymentMethodTokenData] {
        if #available(iOS 11.0, *) {
            return AppState.current.paymentMethods
        } else {
            return AppState.current.paymentMethods.filter { $0.paymentInstrumentType == .paymentCard }
        }
    }

    var selectedPaymentMethod: PrimerPaymentMethodTokenData? {
        return AppState.current.selectedPaymentMethod
    }

    deinit {
        log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
    }
}

#endif

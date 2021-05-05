//
//  SessionType.swift
//  PrimerSDK
//
//  Created by Carl Eriksson on 13/01/2021.
//

/**
 Enum that contains possible values for the drop-in UI flow.
 
 *Values*
 
 `default`: Cannot be added in vault and uses the checkout flow.
 
 `defaultWithVault`: Can be added in vault and uses the vault flow.
 
 `completeDirectCheckout`: Cannot be added in vault and uses the checkout flow.
 
 `addPayPalToVault`: Can be added in vault and uses the vault flow.
 
 `addCardToVault`: Can be added in vault and uses the vault flow.
 
 `addDirectDebitToVault`: Can be added in vault and uses the vault flow.
 
 `addKlarnaToVault`: Can be added in vault and uses the vault flow.
 
 `addDirectDebit`: Can be added in vault and uses the vault flow.
 
 `checkoutWithKlarna`: Can be added in vault and uses the checkout flow.
 
 - Author:
 Primer
 - Version:
 1.2.2
 */

public enum PrimerSessionFlow {

    case vault
    case checkout
    case vaultCard
    case checkoutWithCard
    case vaultPayPal
    case checkoutWithPayPal
    case vaultDirectDebit
    case vaultKlarna
    case checkoutWithKlarna
    
    var vaulted: Bool {
        switch self {
        case .vault,
             .vaultCard,
             .vaultPayPal,
             .vaultDirectDebit,
             .vaultKlarna:
            return true
        case .checkout,
             .checkoutWithCard,
             .checkoutWithPayPal,
             .checkoutWithKlarna:
            return false
        
        }
    }

    var uxMode: UXMode {
        switch self {
        case .vault,
             .vaultCard,
             .vaultPayPal,
             .vaultDirectDebit,
             .vaultKlarna:
            return .VAULT
        case .checkout,
             .checkoutWithCard,
             .checkoutWithPayPal,
             .checkoutWithKlarna:
            return .CHECKOUT
        }
    }
}

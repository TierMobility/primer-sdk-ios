//
//  ConfirmMandateViewModel.swift
//  PrimerSDK
//
//  Created by Carl Eriksson on 21/01/2021.
//

protocol ConfirmMandateViewModelProtocol {
    var mandate: DirectDebitMandate { get }
    var formCompleted: Bool { get set }
    var businessDetails: BusinessDetails? { get }
    var amount: String { get }
    func loadConfig(_ completion: @escaping (Error?) -> Void)
    func confirmMandateAndTokenize(_ completion: @escaping (Error?) -> Void)
    func eraseData()
}

class ConfirmMandateViewModel: ConfirmMandateViewModelProtocol {
    var mandate: DirectDebitMandate {
        return state.directDebitMandate
    }
    
    var formCompleted: Bool {
        get { return state.directDebitFormCompleted }
        set { state.directDebitFormCompleted = newValue }
    }
    
    var businessDetails: BusinessDetails? {
        return state.settings.businessDetails
    }
    
    var amount: String {
        if (state.settings.directDebitHasNoAmount) { return "" }
        return state.settings.amount.toCurrencyString(currency: state.settings.currency)
    }
    
    @Dependency private(set) var state: AppStateProtocol
    @Dependency private(set) var directDebitService: DirectDebitServiceProtocol
    @Dependency private(set) var tokenizationService: TokenizationServiceProtocol
    @Dependency private(set) var paymentMethodConfigService: PaymentMethodConfigServiceProtocol
    @Dependency private(set) var clientTokenService: ClientTokenServiceProtocol
    @Dependency private(set) var vaultService: VaultServiceProtocol
    
    func loadConfig(_ completion: @escaping (Error?) -> Void) {
        if (state.decodedClientToken.exists) {
            paymentMethodConfigService.fetchConfig({ [weak self] error in
                if (error.exists) { return completion(error) }
                self?.vaultService.loadVaultedPaymentMethods(completion)
            })
        } else {
            clientTokenService.loadCheckoutConfig({ [weak self] error in
                if (error.exists) { return completion(error) }
                self?.paymentMethodConfigService.fetchConfig({ [weak self] error in
                    if (error.exists) { return completion(error) }
                    self?.vaultService.loadVaultedPaymentMethods(completion)
                })
            })
        }
    }
    
    func confirmMandateAndTokenize(_ completion: @escaping (Error?) -> Void) {
        directDebitService.createMandate({ [weak self] error in
            if (error.exists) { return completion(PrimerError.DirectDebitSessionFailed) }
            
            guard let state = self?.state else { return completion(PrimerError.DirectDebitSessionFailed) }
            
            let request = PaymentMethodTokenizationRequest(
                paymentInstrument: PaymentInstrument(gocardlessMandateId: state.mandateId),
                state: state
            )
            
            self?.tokenizationService.tokenize(request: request) { [weak self] result in
                switch result {
                case .failure(let error): completion(error)
                case .success:
                    
                    self?.state.directDebitMandate = DirectDebitMandate(
                        //        iban: "FR1420041010050500013M02606",
                        address: Address()
                    )
                    
                    completion(nil)
                }
            }
        })
    }
    
    func eraseData() {
        state.directDebitMandate = DirectDebitMandate()
    }
}

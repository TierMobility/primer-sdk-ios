//
//  CardComponentsManager.swift
//  PrimerSDK
//
//  Created by Evangelos Pittas on 6/7/21.
//

#if canImport(UIKit)

import UIKit

@objc
public protocol CardComponentsManagerDelegate {
    /// The cardComponentsManager(_:clientTokenCallback:) can be used to provide the CardComponentsManager with an access token from the merchants backend.
    /// This delegate function is optional since you can initialize the CardComponentsManager with an access token. Still, if the access token is not valid, the CardComponentsManager
    /// will try to acquire an access token through this function.
    @objc optional func cardComponentsManager(_ cardComponentsManager: CardComponentsManager, clientTokenCallback completion: @escaping (String?, Error?) -> Void)
    /// The cardComponentsManager(_:onTokenizeSuccess:) is the only required method, and it will return the payment method token (which
    /// contains all the information needed)
    func cardComponentsManager(_ cardComponentsManager: CardComponentsManager, onTokenizeSuccess paymentMethodToken: PrimerPaymentMethodTokenData)
    /// The cardComponentsManager(_:tokenizationFailedWith:) will return any tokenization errors that have occured.
    @objc optional func cardComponentsManager(_ cardComponentsManager: CardComponentsManager, tokenizationFailedWith errors: [Error])
    /// The cardComponentsManager(_:isLoading:) will return true when the CardComponentsManager is performing an async operation and waiting for a result, false
    /// when loading has finished.
    @objc optional func cardComponentsManager(_ cardComponentsManager: CardComponentsManager, isLoading: Bool)
}

protocol CardComponentsManagerProtocol {
    var cardnumberField: PrimerCardNumberFieldView { get }
    var expiryDateField: PrimerExpiryDateFieldView { get }
    var cvvField: PrimerCVVFieldView { get }
    var cardholderField: PrimerCardholderNameFieldView? { get }
    var delegate: CardComponentsManagerDelegate? { get }
    var customerId: String? { get }
    var merchantIdentifier: String? { get }
    var amount: Int? { get }
    var currency: Currency? { get }
    var decodedJWTToken: DecodedJWTToken? { get }
    var paymentMethodsConfig: PrimerAPIConfiguration? { get }
    
    func tokenize()
}

typealias BillingAddressField = (fieldView: PrimerTextFieldView,
                                 containerFieldView: PrimerCustomFieldView,
                                 isFieldHidden: Bool)

@objc
public class CardComponentsManager: NSObject, CardComponentsManagerProtocol {
    
    public var cardnumberField: PrimerCardNumberFieldView
    public var expiryDateField: PrimerExpiryDateFieldView
    public var cvvField: PrimerCVVFieldView
    public var cardholderField: PrimerCardholderNameFieldView?
    public var billingAddressFieldViews: [PrimerTextFieldView]?
    
    public var delegate: CardComponentsManagerDelegate?
    public var customerId: String?
    public var merchantIdentifier: String?
    public var amount: Int?
    public var currency: Currency?
    internal var decodedJWTToken: DecodedJWTToken? {
        return PrimerAPIConfigurationModule.decodedJWTToken
    }
    internal var paymentMethodsConfig: PrimerAPIConfiguration?
    private(set) public var isLoading: Bool = false
    internal private(set) var paymentMethod: PrimerPaymentMethodTokenData?
    
    deinit {
        setIsLoading(false)
    }
    
    /// The CardComponentsManager can be initialized with/out an access token. In the case that is initialized without an access token, the delegate function cardComponentsManager(_:clientTokenCallback:) will be called. You can initialize an instance (representing a session) by registering the necessary PrimerTextFieldViews
    public init(
        cardnumberField: PrimerCardNumberFieldView,
        expiryDateField: PrimerExpiryDateFieldView,
        cvvField: PrimerCVVFieldView,
        cardholderNameField: PrimerCardholderNameFieldView?,
        billingAddressFieldViews: [PrimerTextFieldView]?
    ) {
        self.cardnumberField = cardnumberField
        self.expiryDateField = expiryDateField
        self.cvvField = cvvField
        self.cardholderField = cardholderNameField
        self.billingAddressFieldViews = billingAddressFieldViews
        super.init()
    }
    
    internal func setIsLoading(_ isLoading: Bool) {
        if self.isLoading == isLoading { return }
        self.isLoading = isLoading
        delegate?.cardComponentsManager?(self, isLoading: isLoading)
    }
    
    private func fetchClientToken() -> Promise<DecodedJWTToken> {
        return Promise { seal in
            guard let delegate = delegate else {
                print("WARNING!\nDelegate has not been set")
                let err = PrimerError.missingPrimerDelegate(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
                ErrorHandler.handle(error: err)
                seal.reject(err)
                return
            }
            
            delegate.cardComponentsManager?(self, clientTokenCallback: { clientToken, error in
                guard error == nil, let clientToken = clientToken else {
                    seal.reject(error!)
                    return
                }
                
                let apiConfigurationModule = PrimerAPIConfigurationModule()
                firstly {
                    apiConfigurationModule.setupSession(
                        forClientToken: clientToken,
                        requestDisplayMetadata: false,
                        requestClientTokenValidation: false,
                        requestVaultedPaymentMethods: false)
                }
                .done {
                    if let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken {
                        seal.fulfill(decodedJWTToken)
                    } else {
                        precondition(false, "Decoded client token should never be null at this point.")
                        let err = PrimerError.invalidValue(key: "self.decodedClientToken", value: nil, userInfo: nil, diagnosticsId: nil)
                        ErrorHandler.handle(error: err)
                        seal.reject(err)
                    }
                }
                .catch { err in
                    seal.reject(err)
                }
            })
        }
    }
    
    private func fetchClientTokenIfNeeded() -> Promise<DecodedJWTToken> {
        return Promise { seal in
            do {
                if let decodedJWTToken = decodedJWTToken {
                    try decodedJWTToken.validate()
                    seal.fulfill(decodedJWTToken)
                } else {
                    firstly {
                        self.fetchClientToken()
                    }
                    .done { decodedJWTToken in
                        seal.fulfill(decodedJWTToken)
                    }
                    .catch { err in
                        seal.reject(err)
                    }
                }
                
            } catch {
                switch error {
                case PrimerError.invalidClientToken:
                    firstly {
                        self.fetchClientToken()
                    }
                    .done { decodedJWTToken in
                        seal.fulfill(decodedJWTToken)
                    }
                    .catch { err in
                        seal.reject(err)
                    }
                default:
                    seal.reject(error)
                }
            }
            
        }
    }
    
    private func validateCardComponents() throws {
        var errors: [Error] = []
        
        if !cardnumberField.cardnumber.isValidCardNumber {
            errors.append(PrimerValidationError.invalidCardnumber(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil))
        }
        
        if expiryDateField.expiryMonth == nil || expiryDateField.expiryYear == nil {
            errors.append(PrimerValidationError.invalidExpiryDate(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil))
        }
        
        if !cvvField.cvv.isValidCVV(cardNetwork: CardNetwork(cardNumber: cardnumberField.cardnumber)) {
            errors.append(PrimerValidationError.invalidCvv(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil))
        }
        
        billingAddressFieldViews?.filter { $0.isTextValid == false }.forEach {
            if let simpleCardFormTextFieldView = $0 as? PrimerSimpleCardFormTextFieldView,
               let validationError = simpleCardFormTextFieldView.validationError {
                ErrorHandler.handle(error: validationError)
                errors.append(validationError)
            }
        }
        
        if !errors.isEmpty {
            let err = PrimerError.underlyingErrors(errors: errors, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
            ErrorHandler.handle(error: err)
            throw err
        }
    }
    
    public func tokenize() {
        do {
            setIsLoading(true)
            
            try validateCardComponents()
            
            firstly {
                self.fetchClientTokenIfNeeded()
            }
            .done { _ in
                self.paymentMethodsConfig = PrimerAPIConfigurationModule.apiConfiguration
                
                let paymentInstrument = CardPaymentInstrument(
                    number: self.cardnumberField.cardnumber,
                    cvv: self.cvvField.cvv,
                    expirationMonth: self.expiryDateField.expiryMonth!,
                    expirationYear: "20" + self.expiryDateField.expiryYear!,
                    cardholderName: self.cardholderField?.cardholderName)
                
                let tokenizationService: TokenizationServiceProtocol = TokenizationService()
                let requestBody = Request.Body.Tokenization(paymentInstrument: paymentInstrument)
                
                firstly {
                    return tokenizationService.tokenize(requestBody: requestBody)
                }
                .done { paymentMethodTokenData in
                    var isThreeDSEnabled: Bool = false
                    if PrimerAPIConfigurationModule.apiConfiguration?.paymentMethods?.filter({ ($0.options as? CardOptions)?.threeDSecureEnabled == true }).count ?? 0 > 0 {
                        isThreeDSEnabled = true
                    }
                    
                    /// 3DS requirements on tokenization are:
                    ///     - The payment method has to be a card
                    ///     - It has to be a vault flow
                    ///     - is3DSOnVaultingEnabled has to be enabled by the developer
                    ///     - 3DS has to be enabled int he payment methods options in the config object (returned by the config API call)
                    if paymentMethodTokenData.paymentInstrumentType == .paymentCard,
                       PrimerInternal.shared.intent == .vault,
                       PrimerSettings.current.paymentMethodOptions.cardPaymentOptions.is3DSOnVaultingEnabled,
                       paymentMethodTokenData.threeDSecureAuthentication?.responseCode != ThreeDS.ResponseCode.authSuccess,
                       isThreeDSEnabled {
#if canImport(Primer3DS)
                        let threeDSService: ThreeDSServiceProtocol = ThreeDSService()
                        DependencyContainer.register(threeDSService)
                        
                        var beginAuthExtraData: ThreeDS.BeginAuthExtraData
                        do {
                            beginAuthExtraData = try ThreeDSService.buildBeginAuthExtraData()
                        } catch {
                            self.paymentMethod = paymentMethodTokenData
                            self.delegate?.cardComponentsManager(self, onTokenizeSuccess: paymentMethodTokenData)
                            return
                        }
                        
                        guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                            let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
                            ErrorHandler.handle(error: err)
                            self.delegate?.cardComponentsManager?(self, tokenizationFailedWith: [err])
                            return
                        }
                        
                        threeDSService.perform3DS(
                            paymentMethodTokenData: paymentMethodTokenData,
                            protocolVersion: decodedJWTToken.env == "PRODUCTION" ? .v1 : .v2,
                            beginAuthExtraData: beginAuthExtraData,
                            sdkDismissed: { () in
                                
                            }, completion: { result in
                                switch result {
                                case .success(let res):
                                    self.delegate?.cardComponentsManager(self, onTokenizeSuccess: res.0)
                                    
                                case .failure(let err):
                                    // Even if 3DS fails, continue...
                                    log(logLevel: .error, message: "3DS failed with error: \(err as NSError), continue without 3DS")
                                    self.delegate?.cardComponentsManager(self, onTokenizeSuccess: paymentMethodTokenData)
                                    
                                }
                            })
                        
#else
                        print("\nWARNING!\nCannot perform 3DS, Primer3DS SDK is missing. Continue without 3DS\n")
                        self.delegate?.cardComponentsManager(self, onTokenizeSuccess: paymentMethodTokenData)
#endif
                        
                    } else {
                        self.delegate?.cardComponentsManager(self, onTokenizeSuccess: paymentMethodTokenData)
                    }
                }
                .catch { err in
                    let containerErr = PrimerError.underlyingErrors(errors: [err], userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
                    ErrorHandler.handle(error: containerErr)
                    self.delegate?.cardComponentsManager?(self, tokenizationFailedWith: [err])
                }
            }
            .catch { err in
                self.delegate?.cardComponentsManager?(self, tokenizationFailedWith: [err])
                self.setIsLoading(false)
            }
        } catch PrimerError.underlyingErrors(errors: let errors, userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil) {
            delegate?.cardComponentsManager?(self, tokenizationFailedWith: errors)
            setIsLoading(false)
        } catch {
            delegate?.cardComponentsManager?(self, tokenizationFailedWith: [error])
            setIsLoading(false)
        }
    }
    
}

internal class MockCardComponentsManager: CardComponentsManagerProtocol {
    
    var cardnumberField: PrimerCardNumberFieldView
    
    var expiryDateField: PrimerExpiryDateFieldView
    
    var cvvField: PrimerCVVFieldView
    
    var cardholderField: PrimerCardholderNameFieldView?
    
    var postalCodeField: PrimerPostalCodeFieldView?
    
    var delegate: CardComponentsManagerDelegate?
    
    var customerId: String?
    
    var merchantIdentifier: String?
    
    var amount: Int?
    
    var currency: Currency?
    
    var decodedJWTToken: DecodedJWTToken? {
        return PrimerAPIConfigurationModule.decodedJWTToken
    }
    
    var paymentMethodsConfig: PrimerAPIConfiguration?
    
    public init(
        cardnumberField: PrimerCardNumberFieldView,
        expiryDateField: PrimerExpiryDateFieldView,
        cvvField: PrimerCVVFieldView,
        cardholderNameField: PrimerCardholderNameFieldView?,
        postalCodeField: PrimerPostalCodeFieldView
    ) {
        self.cardnumberField = cardnumberField
        self.expiryDateField = expiryDateField
        self.cvvField = cvvField
        self.cardholderField = cardholderNameField
        self.postalCodeField = postalCodeField
    }
    
    convenience init(
        cardnumber: String?
    ) {
        let cardnumberFieldView = PrimerCardNumberFieldView()
        cardnumberFieldView.textField._text = cardnumber
        self.init(
            cardnumberField: cardnumberFieldView,
            expiryDateField: PrimerExpiryDateFieldView(),
            cvvField: PrimerCVVFieldView(),
            cardholderNameField: PrimerCardholderNameFieldView(),
            postalCodeField: PrimerPostalCodeFieldView()
        )
    }
    
    func tokenize() {
        
    }
    
}

#endif
//
//  ThreeDSService.swift
//  PrimerSDK
//
//  Created by Evangelos Pittas on 17/6/21.
//

#if canImport(UIKit)

import Foundation
import UIKit

#if canImport(Primer3DS)
import Primer3DS
#endif

protocol ThreeDSServiceProtocol {
    
    static var apiClient: PrimerAPIClientProtocol? { get set }
    
    func perform3DS(
        paymentMethodTokenData: PrimerPaymentMethodTokenData,
        sdkDismissed: (() -> Void)?,
        completion: @escaping (_ result: Result<String, Error>) -> Void)
}

class ThreeDSService: ThreeDSServiceProtocol {
    
    static var apiClient: PrimerAPIClientProtocol?
    
    private var threeDSSDKWindow: UIWindow?
    private var initProtocolVersion: ThreeDS.ProtocolVersion?
    private var continueErrorInfo: ThreeDS.ContinueInfo?
    private var resumePaymentToken: String?
    private var demo3DSWindow: UIWindow?
    
#if canImport(Primer3DS)
    private var primer3DS: Primer3DS!
#endif
    
    deinit {
        log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
    }
    
    internal func perform3DS(
        paymentMethodTokenData: PrimerPaymentMethodTokenData,
        sdkDismissed: (() -> Void)?,
        completion: @escaping (_ result: Result<String, Error>) -> Void
    ) {
#if canImport(Primer3DS)
        firstly {
            self.validate()
        }
        .then { () -> Promise<Void> in
            self.initializePrimer3DSSdk()
        }
        .then { () -> Promise<SDKAuthResult> in
            self.create3DsAuthData(paymentMethodTokenData: paymentMethodTokenData)
        }
        .then { sdkAuthResult -> Promise<(serverAuthData: ThreeDS.ServerAuthData, resumeToken: String, threeDsAppRequestorUrl: URL?)> in
            self.initProtocolVersion = ThreeDS.ProtocolVersion(rawValue: sdkAuthResult.maxSupportedThreeDsProtocolVersion)
            return self.initialize3DSAuthorization(sdkAuthResult: sdkAuthResult, paymentMethodTokenData: paymentMethodTokenData)
        }
        .then { result -> Promise<Primer3DSCompletion> in
            self.resumePaymentToken = result.resumeToken
            return self.perform3DSChallenge(threeDSAuthData: result.serverAuthData, threeDsAppRequestorUrl: result.threeDsAppRequestorUrl)
        }
        .then { primer3DSCompletion -> Promise<ThreeDS.PostAuthResponse> in
            sdkDismissed?()
            return self.finalize3DSAuthorization(
                paymentMethodToken: paymentMethodTokenData.token,
                continueInfo: nil)
        }
        .done { result in
            self.resumePaymentToken = result.resumeToken
            completion(.success(result.resumeToken))
        }
        .ensure {
            let dismiss3DSUIEvent = Analytics.Event(
                eventType: .ui,
                properties: UIEventProperties(
                    action: .dismiss,
                    context: nil,
                    extra: nil,
                    objectType: .thirdPartyView,
                    objectId: nil,
                    objectClass: nil,
                    place: .threeDSScreen))
            Analytics.Service.record(events: [dismiss3DSUIEvent])
            
            self.threeDSSDKWindow?.isHidden = true
            self.threeDSSDKWindow = nil
        }
        .catch { err in
            var continueInfo: ThreeDS.ContinueInfo?
            
            if case InternalError.noNeedToPerform3ds(let status) = err {
                precondition(false, "Should always have resumeToken by now")
                
                guard let resumePaymentToken = self.resumePaymentToken else {
                    let err = PrimerError.invalidValue(
                        key: "resumeToken",
                        value: nil,
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    completion(.failure(err))
                    return
                }
                
                completion(.success(resumePaymentToken))
                return
                
            } else if case InternalError.failedToPerform3dsAndShouldBreak(let error) = err {
                ErrorHandler.handle(error: error)
                completion(.failure(error))
                return
                
            } else if case InternalError.failedToPerform3dsButShouldContinue(let primer3DSErrorContainer) = err {
                ErrorHandler.handle(error: primer3DSErrorContainer)
                continueInfo = primer3DSErrorContainer.continueInfo
                
            } else {
                ErrorHandler.handle(error: err)
            }

            firstly {
                self.finalize3DSAuthorization(paymentMethodToken: paymentMethodTokenData.token, continueInfo: continueInfo)
            }
            .done { result in
                let tmpResumePaymentToken = result.resumeToken ?? self.resumePaymentToken
                
                guard let resumePaymentToken = tmpResumePaymentToken else {
                    let err = PrimerError.invalidValue(
                        key: "resumeToken",
                        value: nil,
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: UUID().uuidString)
                    ErrorHandler.handle(error: err)
                    completion(.failure(err))
                    return
                }
                
                completion(.success(resumePaymentToken))
            }
            .catch { err in
                completion(.failure(err))
            }
        }
        
#else
        let missingSdkErr = Primer3DSErrorContainer.missingSdkDependency(
            userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
            diagnosticsId: UUID().uuidString)
        ErrorHandler.handle(error: missingSdkErr)
        
        let continueErrorInfo = missingSdkErr.continueInfo
        
        firstly {
            self.validate()
        }
        .then { () -> Promise<ThreeDS.PostAuthResponse> in
            self.finalize3DSAuthorization(paymentMethodToken: paymentMethodTokenData.token, continueInfo: continueErrorInfo)
        }
        .done { threeDsAuth in
            self.resumePaymentToken = threeDsAuth.resumeToken
            completion(.success(threeDsAuth.resumeToken))
        }
        .catch { err in
            completion(.failure(err))
        }
#endif
    }
    
    private func validate() -> Promise<Void> {
        return Promise { seal in
            guard PrimerAPIConfigurationModule.decodedJWTToken != nil else {
                let uuid = UUID().uuidString
                
                let err = PrimerError.invalidClientToken(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: uuid)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                seal.reject(internalErr)
                return
            }
            
            guard AppState.current.apiConfiguration != nil else {
                let uuid = UUID().uuidString
                
                let err = PrimerError.missingPrimerConfiguration(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: uuid)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                seal.reject(internalErr)
                return
            }
            
            seal.fulfill(())
        }
    }
    
#if canImport(Primer3DS)
    private func initializePrimer3DSSdk() -> Promise<Void> {
        return Promise { seal in
            guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                precondition(false, "It's already validated in the validate()")
                
                let err = PrimerError.invalidClientToken(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: UUID().uuidString)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                seal.reject(internalErr)
                return
            }
            
            guard let apiConfiguration = AppState.current.apiConfiguration else {
                precondition(false, "It's already validated in the validate()")
                let err = PrimerError.missingPrimerConfiguration(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: UUID().uuidString)
                ErrorHandler.handle(error: err)
                seal.reject(err)
                return
            }
            
            guard let licenseKey = apiConfiguration.keys?.netceteraLicenseKey else {
                let uuid = UUID().uuidString
                
                let err = Primer3DSErrorContainer.missing3DSConfiguration(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: uuid,
                    missingKey: "netceteraLicenseKey")
                
                let internalError = InternalError.failedToPerform3dsButShouldContinue(error: err)
                
                seal.reject(internalError)
                return
            }
            
            var certs: [Primer3DSCertificate] = []
            for certificate in AppState.current.apiConfiguration?.keys?.threeDSecureIoCertificates ?? [] {
                let cer = ThreeDS.Cer(cardScheme: certificate.cardNetwork, rootCertificate: certificate.rootCertificate, encryptionKey: certificate.encryptionKey)
                certs.append(cer)
            }
            
            let useThreeDsWeakValidation = decodedJWTToken.useThreeDsWeakValidation == false ? false : true
            
            switch Environment(rawValue: decodedJWTToken.env ?? "") {
            case .production:
                primer3DS = Primer3DS(environment: .production)
            case .staging:
                primer3DS = Primer3DS(environment: .staging)
            default:
                primer3DS = Primer3DS(environment: .sandbox)
            }
            
            // ⚠️  Property version doesn't exist on version before 1.1.0, so PrimerSDK won't build
            //     if Primer3DS is not equal or above 1.1.0
            if Primer3DS.version?.compareWithVersion("1.0") == .orderedDescending {
                do {
                    primer3DS.is3DSSanityCheckEnabled = PrimerSettings.current.debugOptions.is3DSSanityCheckEnabled
                    try primer3DS.initializeSDK(licenseKey: licenseKey, certificates: certs, enableWeakValidation: useThreeDsWeakValidation)
                    seal.fulfill(())
                    
                } catch {
                    let uuid = UUID().uuidString
                    
                    if let primer3DSError = error as? Primer3DSError {
                        let err = Primer3DSErrorContainer.primer3DSSdkError(
                            userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                            diagnosticsId: uuid,
                            initProtocolVersion: self.initProtocolVersion?.rawValue,
                            errorInfo: Primer3DSErrorInfo(
                                errorId: primer3DSError.errorId,
                                errorDescription: primer3DSError.errorDescription,
                                recoverySuggestion: primer3DSError.recoverySuggestion,
                                threeDsErrorCode: primer3DSError.threeDsErrorCode,
                                threeDsErrorType: primer3DSError.threeDsErrorType,
                                threeDsErrorComponent: primer3DSError.threeDsErrorComponent,
                                threeDsSdkTranscationId: primer3DSError.threeDsSdkTranscationId,
                                threeDsSErrorVersion: primer3DSError.threeDsSErrorVersion,
                                threeDsErrorDetail: primer3DSError.threeDsErrorDetail))
                        
                        let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                        seal.reject(internalErr)
                        
                    } else {
                        precondition(false, "Should always receive Primer3DSError")
                        let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: error)
                        seal.reject(internalErr)
                    }
                }
                
            } else {
                let uuid = UUID().uuidString
                
                let err = Primer3DSErrorContainer.invalid3DSSdkVersion(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: uuid,
                    invalidVersion: Primer3DS.version,
                    validVersion: "1.1.0")
                
                let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                seal.reject(internalErr)
            }
        }
    }
    
    private func create3DsAuthData(paymentMethodTokenData: PrimerPaymentMethodTokenData) -> Promise<SDKAuthResult> {
        return Promise { seal in
            guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                precondition(false, "It's already validated in the validate()")
                
                let err = PrimerError.invalidClientToken(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: UUID().uuidString)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                seal.reject(internalErr)
                return
            }
            
            let cardNetwork = CardNetwork(cardNetworkStr: paymentMethodTokenData.paymentInstrumentData?.binData?.network ?? "")
            
            guard let directoryServerId = cardNetwork.directoryServerId else {
                let uuid = UUID().uuidString
                
                let primer3DSError = Primer3DSError.missingDsRid(
                    cardNetwork: paymentMethodTokenData.paymentInstrumentData?.binData?.network ?? "n/a")
                
                let err = Primer3DSErrorContainer.primer3DSSdkError(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: uuid,
                    initProtocolVersion: self.initProtocolVersion?.rawValue,
                    errorInfo: Primer3DSErrorInfo(
                        errorId: primer3DSError.errorId,
                        errorDescription: primer3DSError.errorDescription,
                        recoverySuggestion: primer3DSError.recoverySuggestion,
                        threeDsErrorCode: primer3DSError.threeDsErrorCode,
                        threeDsErrorType: primer3DSError.threeDsErrorType,
                        threeDsErrorComponent: primer3DSError.threeDsErrorComponent,
                        threeDsSdkTranscationId: primer3DSError.threeDsSdkTranscationId,
                        threeDsSErrorVersion: primer3DSError.threeDsSErrorVersion,
                        threeDsErrorDetail: primer3DSError.threeDsErrorDetail))
                
                let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                seal.reject(internalErr)
                return
            }
            
            let supportedThreeDsProtocolVersions = decodedJWTToken.supportedThreeDsProtocolVersions ?? []
                        
            do {
                let result = try self.primer3DS.createTransaction(
                    directoryServerId: directoryServerId,
                    supportedThreeDsProtocolVersions: supportedThreeDsProtocolVersions)
                seal.fulfill(result)
                
            } catch {
                let uuid = UUID().uuidString
                
                if let primer3DSError = error as? Primer3DSError {
                    let err = Primer3DSErrorContainer.primer3DSSdkError(
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: uuid,
                        initProtocolVersion: self.initProtocolVersion?.rawValue,
                        errorInfo: Primer3DSErrorInfo(
                            errorId: primer3DSError.errorId,
                            errorDescription: primer3DSError.errorDescription,
                            recoverySuggestion: primer3DSError.recoverySuggestion,
                            threeDsErrorCode: primer3DSError.threeDsErrorCode,
                            threeDsErrorType: primer3DSError.threeDsErrorType,
                            threeDsErrorComponent: primer3DSError.threeDsErrorComponent,
                            threeDsSdkTranscationId: primer3DSError.threeDsSdkTranscationId,
                            threeDsSErrorVersion: primer3DSError.threeDsSErrorVersion,
                            threeDsErrorDetail: primer3DSError.threeDsErrorDetail))
                    
                    let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                    seal.reject(internalErr)
                    
                } else {
                    precondition(false, "Should always receive Primer3DSError")
                    let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: error)
                    seal.reject(internalErr)
                }
            }
        }
    }
    
    private func initialize3DSAuthorization(
        sdkAuthResult: SDKAuthResult,
        paymentMethodTokenData: PrimerPaymentMethodTokenData
    ) -> Promise<(serverAuthData: ThreeDS.ServerAuthData, resumeToken: String, threeDsAppRequestorUrl: URL?)> {
        return Promise { seal in
            var threeDsAppRequestorUrl: URL?
            
            if sdkAuthResult.maxSupportedThreeDsProtocolVersion.compareWithVersion("2.1") == .orderedDescending {
                if let urlStr = PrimerSettings.current.threeDsOptions.threeDsAppRequestorUrl,
                   urlStr.hasPrefix("https"),
                   let url = URL(string: urlStr)
                {
                    // All good, url value is valid and https
                    threeDsAppRequestorUrl = url
                } else {
                    print("PRIMER WARNING!\nthreeDsAppRequestorUrl is not in a valid format (\"https://applink\"). In case you want to support redirecting back during the OOB flows please set correct threeDsAppRequestorUrl in PrimerThreeDsOptions during SDK initialization.")
                }
            }
            
            let threeDSecureBeginAuthRequest = ThreeDS.BeginAuthRequest(
                maxProtocolVersion: sdkAuthResult.maxSupportedThreeDsProtocolVersion,
                device: ThreeDS.SDKAuthData(
                    sdkAppId: sdkAuthResult.authData.sdkAppId,
                    sdkTransactionId: sdkAuthResult.authData.sdkTransactionId,
                    sdkTimeout: sdkAuthResult.authData.sdkTimeout,
                    sdkEncData: sdkAuthResult.authData.sdkEncData,
                    sdkEphemPubKey: sdkAuthResult.authData.sdkEphemPubKey,
                    sdkReferenceNumber: sdkAuthResult.authData.sdkReferenceNumber))
            
            self.requestInitialize3DSAuthorization(
                paymentMethodTokenData: paymentMethodTokenData,
                threeDSecureBeginAuthRequest: threeDSecureBeginAuthRequest) { result in
                    switch result {
                    case .success(let beginAuthResponse):
                        switch beginAuthResponse.authentication.responseCode {
                        case .authSuccess,
                                .authFailed,
                                .METHOD,        // Only applies on Web
                                .notPerformed,
                                .skipped:
                            
                            let internalErr = InternalError.noNeedToPerform3ds(
                                status: beginAuthResponse.authentication.responseCode.rawValue)
                            seal.reject(internalErr)
                            
                        case .challenge:
                            let serverAuthData = ThreeDS.ServerAuthData(acsReferenceNumber: beginAuthResponse.authentication.acsReferenceNumber,
                                                                        acsSignedContent: beginAuthResponse.authentication.acsSignedContent,
                                                                        acsTransactionId: beginAuthResponse.authentication.acsTransactionId,
                                                                        responseCode: beginAuthResponse.authentication.responseCode.rawValue,
                                                                        transactionId: beginAuthResponse.authentication.transactionId)
                            
                            seal.fulfill((serverAuthData, beginAuthResponse.resumeToken, threeDsAppRequestorUrl))
                        }
                        
                    case .failure(let error):
                        seal.reject(error)
                    }
                }
        }
    }
    
    private func perform3DSChallenge(
        threeDSAuthData: Primer3DSServerAuthData,
        threeDsAppRequestorUrl: URL?
    ) -> Promise<Primer3DSCompletion> {
        return Promise { seal in
            var isMockedBE = false
#if DEBUG
            if PrimerAPIConfiguration.current?.clientSession?.testId != nil {
                isMockedBE = true
            }
#endif
            if !isMockedBE {
                guard let primer3DS = primer3DS else {
                    precondition(false, "Primer3DS should have been initialized")
                    
                    let uuid = UUID().uuidString
                    
                    let primer3DSError = Primer3DSError.initializationError(error: nil, warnings: "Uninitialized SDK")
                    
                    let err = Primer3DSErrorContainer.primer3DSSdkError(
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: uuid,
                        initProtocolVersion: self.initProtocolVersion?.rawValue,
                        errorInfo: Primer3DSErrorInfo(
                            errorId: primer3DSError.errorId,
                            errorDescription: primer3DSError.errorDescription,
                            recoverySuggestion: primer3DSError.recoverySuggestion,
                            threeDsErrorCode: primer3DSError.threeDsErrorCode,
                            threeDsErrorType: primer3DSError.threeDsErrorType,
                            threeDsErrorComponent: primer3DSError.threeDsErrorComponent,
                            threeDsSdkTranscationId: primer3DSError.threeDsSdkTranscationId,
                            threeDsSErrorVersion: primer3DSError.threeDsSErrorVersion,
                            threeDsErrorDetail: primer3DSError.threeDsErrorDetail))
                    
                    let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                    seal.reject(internalErr)
                    return
                }
                
                if #available(iOS 13.0, *) {
                    if let windowScene = UIApplication.shared.connectedScenes.filter({ $0.activationState == .foregroundActive }).first as? UIWindowScene {
                        self.threeDSSDKWindow = UIWindow(windowScene: windowScene)
                    } else {
                        // Not opted-in in UISceneDelegate
                        self.threeDSSDKWindow = UIWindow(frame: UIScreen.main.bounds)
                    }
                } else {
                    // Fallback on earlier versions
                    self.threeDSSDKWindow = UIWindow(frame: UIScreen.main.bounds)
                }
                
                self.threeDSSDKWindow!.rootViewController = ClearViewController()
                self.threeDSSDKWindow!.backgroundColor = UIColor.clear
                self.threeDSSDKWindow!.windowLevel = UIWindow.Level.normal
                self.threeDSSDKWindow!.makeKeyAndVisible()
                
                let present3DSUIEvent = Analytics.Event(
                    eventType: .ui,
                    properties: UIEventProperties(
                        action: Analytics.Event.Property.Action.present,
                        context: nil,
                        extra: nil,
                        objectType: .thirdPartyView,
                        objectId: nil,
                        objectClass: nil,
                        place: .threeDSScreen))
                Analytics.Service.record(events: [present3DSUIEvent])
                
                primer3DS.performChallenge(
                    threeDSAuthData: threeDSAuthData,
                    threeDsAppRequestorUrl: threeDsAppRequestorUrl,
                    presentOn: self.threeDSSDKWindow!.rootViewController!) { primer3DSCompletion, err in
                        if let primer3DSError = err as? Primer3DSError {
                            let err = Primer3DSErrorContainer.primer3DSSdkError(
                                userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                                diagnosticsId: UUID().uuidString,
                                initProtocolVersion: self.initProtocolVersion?.rawValue,
                                errorInfo: Primer3DSErrorInfo(
                                    errorId: primer3DSError.errorId,
                                    errorDescription: primer3DSError.errorDescription,
                                    recoverySuggestion: primer3DSError.recoverySuggestion,
                                    threeDsErrorCode: primer3DSError.threeDsErrorCode,
                                    threeDsErrorType: primer3DSError.threeDsErrorType,
                                    threeDsErrorComponent: primer3DSError.threeDsErrorComponent,
                                    threeDsSdkTranscationId: primer3DSError.threeDsSdkTranscationId,
                                    threeDsSErrorVersion: primer3DSError.threeDsSErrorVersion,
                                    threeDsErrorDetail: primer3DSError.threeDsErrorDetail))
                            
                            let internalErr = InternalError.failedToPerform3dsButShouldContinue(error: err)
                            seal.reject(internalErr)
                            
                        } else if let primer3DSCompletion = primer3DSCompletion {
                            seal.fulfill(primer3DSCompletion)
                            
                        } else {
                            precondition(false, "Should always receive an error or a completion")
                            
                            let err = PrimerError.invalidValue(
                                key: "performChallenge.result",
                                value: nil,
                                userInfo: nil,
                                diagnosticsId: UUID().uuidString)
                            let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                            seal.reject(internalErr)
                        }
                    }
                
            } else {
                if #available(iOS 13.0, *) {
                    if let windowScene = UIApplication.shared.connectedScenes.filter({ $0.activationState == .foregroundActive }).first as? UIWindowScene {
                        demo3DSWindow = UIWindow(windowScene: windowScene)
                    } else {
                        // Not opted-in in UISceneDelegate
                        demo3DSWindow = UIWindow(frame: UIScreen.main.bounds)
                    }
                } else {
                    // Fallback on earlier versions
                    demo3DSWindow = UIWindow(frame: UIScreen.main.bounds)
                }

                demo3DSWindow!.rootViewController = ClearViewController()
                demo3DSWindow!.backgroundColor = UIColor.clear
                demo3DSWindow!.windowLevel = UIWindow.Level.alert
                demo3DSWindow!.makeKeyAndVisible()
                
                let vc = PrimerDemo3DSViewController()
                demo3DSWindow!.rootViewController?.present(vc, animated: true)
                
                vc.onSendCredentialsButtonTapped = {
                    self.demo3DSWindow?.rootViewController = nil
                    self.demo3DSWindow = nil
                    seal.fulfill(MockPrimer3DSCompletion())
                }
            }
        }
    }
    
    private func requestInitialize3DSAuthorization(
        paymentMethodTokenData: PrimerPaymentMethodTokenData,
        threeDSecureBeginAuthRequest: ThreeDS.BeginAuthRequest,
        completion: @escaping (Result<ThreeDS.BeginAuthResponse, Error>) -> Void
    ) {
        guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
            precondition(false, "It's already validated in the validate()")
            
            let err = PrimerError.invalidClientToken(
                userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                diagnosticsId: UUID().uuidString)
            
            let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
            completion(.failure(internalErr))
            return
        }
        
        let apiClient: PrimerAPIClientProtocol = ThreeDSService.apiClient ?? PrimerAPIClient()
        apiClient.begin3DSAuth(clientToken: decodedJWTToken, paymentMethodTokenData: paymentMethodTokenData, threeDSecureBeginAuthRequest: threeDSecureBeginAuthRequest, completion: { result in
            switch result {
            case .failure(let underlyingErr):
                var primerErr: PrimerError
                
                if let primerError = underlyingErr as? PrimerError {
                    primerErr = primerError
                } else {
                    primerErr = PrimerError.underlyingErrors(
                        errors: [underlyingErr],
                        userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                        diagnosticsId: UUID().uuidString)
                }
                
                ErrorHandler.handle(error: primerErr)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: primerErr)
                completion(.failure(internalErr))
                
            case .success(let res):
                completion(.success(res))
            }
        })
    }
#endif
    
    private func finalize3DSAuthorization(
        paymentMethodToken: String,
        continueInfo: ThreeDS.ContinueInfo?
    ) -> Promise<ThreeDS.PostAuthResponse> {
        return Promise { seal in
            guard let decodedJWTToken = PrimerAPIConfigurationModule.decodedJWTToken else {
                precondition(false, "It's already validated in the validate()")
                
                let err = PrimerError.invalidClientToken(
                    userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                    diagnosticsId: UUID().uuidString)
                
                let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: err)
                seal.reject(internalErr)
                return
            }
            
            let apiClient: PrimerAPIClientProtocol = ThreeDSService.apiClient ?? PrimerAPIClient()
            apiClient.continue3DSAuth(
                clientToken: decodedJWTToken,
                threeDSTokenId: paymentMethodToken,
                continueInfo: continueInfo ?? ThreeDS.ContinueInfo(initProtocolVersion: self.initProtocolVersion?.rawValue, error: nil)
            ) { result in
                switch result {
                case .failure(let underlyingErr):
                    var primerErr: PrimerError
                    
                    if let primerError = underlyingErr as? PrimerError {
                        primerErr = primerError
                    } else {
                        primerErr = PrimerError.underlyingErrors(
                            errors: [underlyingErr],
                            userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"],
                            diagnosticsId: UUID().uuidString)
                    }
                                        
                    let internalErr = InternalError.failedToPerform3dsAndShouldBreak(error: primerErr)
                    seal.reject(internalErr)
                    
                case .success(let res):
                    seal.fulfill(res)
                }
            }
        }
    }
    
    private func handleError() {
        
    }
}

#if canImport(Primer3DS)
internal class MockPrimer3DSCompletion: Primer3DSCompletion {
    var sdkTransactionId: String = "sdk-transaction-id"
    var transactionStatus: String = "transactionStatus"
}
#endif

#endif

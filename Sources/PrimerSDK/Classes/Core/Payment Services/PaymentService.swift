//
//  CreateResumePaymentService.swift
//  PrimerSDK
//
//  Created by Dario Carlomagno on 24/02/22.
//

#if canImport(UIKit)

import Foundation

internal protocol PaymentServiceProtocol {
    static var apiClient: PrimerAPIClientProtocol? { get set }
    func createPayment(paymentRequest: Request.Body.Payment.Create, completion: @escaping (Response.Body.Payment?, Error?) -> Void)
    func resumePaymentWithPaymentId(_ paymentId: String, paymentResumeRequest: Request.Body.Payment.Resume, completion: @escaping (Response.Body.Payment?, Error?) -> Void)
}

internal class PaymentService: PaymentServiceProtocol {
    
    static var apiClient: PrimerAPIClientProtocol?
    
    deinit {
        log(logLevel: .debug, message: "🧨 deinit: \(self) \(Unmanaged.passUnretained(self).toOpaque())")
    }

    func createPayment(paymentRequest: Request.Body.Payment.Create, completion: @escaping (Response.Body.Payment?, Error?) -> Void) {
        guard let clientToken = PrimerAPIConfigurationModule.decodedJWTToken else {
            let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
            ErrorHandler.handle(error: err)
            completion(nil, err)
            return
        }
        
        let apiClient: PrimerAPIClientProtocol = PaymentService.apiClient ?? PrimerAPIClient()
        apiClient.createPayment(clientToken: clientToken, paymentRequestBody: paymentRequest) { result in
            switch result {
            case .failure(let error):
                completion(nil, error)
            case .success(let paymentResponse):
                completion(paymentResponse, nil)
            }
        }
    }
    
    func resumePaymentWithPaymentId(_ paymentId: String, paymentResumeRequest: Request.Body.Payment.Resume, completion: @escaping (Response.Body.Payment?, Error?) -> Void) {
        guard let clientToken = PrimerAPIConfigurationModule.decodedJWTToken else {
            let err = PrimerError.invalidClientToken(userInfo: ["file": #file, "class": "\(Self.self)", "function": #function, "line": "\(#line)"], diagnosticsId: nil)
            ErrorHandler.handle(error: err)
            completion(nil, err)
            return
        }
                
        let apiClient: PrimerAPIClientProtocol = PaymentService.apiClient ?? PrimerAPIClient()
        apiClient.resumePayment(clientToken: clientToken, paymentId: paymentId, paymentResumeRequest: paymentResumeRequest) { result in
            switch result {
            case .failure(let error):
                completion(nil, error)
            case .success(let paymentResponse):
                completion(paymentResponse, nil)
            }
        }

    }
}

#endif
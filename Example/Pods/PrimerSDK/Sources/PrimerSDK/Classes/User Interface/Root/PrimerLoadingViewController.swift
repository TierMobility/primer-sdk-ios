//
//  PrimerLoadingViewController.swift
//  PrimerSDK
//
//  Created by Evangelos Pittas on 30/7/21.
//

#if canImport(UIKit)

import UIKit

/// PrimerLoadingViewController is a loading view controller, with variable height.
class PrimerLoadingViewController: PrimerViewController {
    
    private var height: CGFloat
    private(set) internal var imageView: UIImageView?
    private(set) internal var message: String?
    private(set) internal var activityIndicatorView: UIActivityIndicatorView = UIActivityIndicatorView()
    private(set) internal var resultView: PrimerResultComponentView!
    
    init(height: CGFloat, imageView: UIImageView?, message: String?) {
        self.height = height
        self.imageView = imageView
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let viewEvent = Analytics.Event(
            eventType: .ui,
            properties: UIEventProperties(
                action: .view,
                context: nil,
                extra: nil,
                objectType: .view,
                objectId: nil,
                objectClass: "\(Self.self)",
                place: .sdkLoading))
        Analytics.Service.record(event: viewEvent)
        
        let theme: PrimerThemeProtocol = DependencyContainer.resolve()
        view.backgroundColor = theme.view.backgroundColor
        
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        activityIndicatorView.widthAnchor.constraint(equalToConstant: 50.0).isActive = true
        activityIndicatorView.startAnimating()
        
        resultView = PrimerResultComponentView(frame: .zero, imageView: self.imageView, message: self.message, loadingIndicator: self.activityIndicatorView)
        view.addSubview(resultView)
        resultView.translatesAutoresizingMaskIntoConstraints = false
        resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12).isActive = true
        resultView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 12).isActive = true
        resultView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
    
}

#endif
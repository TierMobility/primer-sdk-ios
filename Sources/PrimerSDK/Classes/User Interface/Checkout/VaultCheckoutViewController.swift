#if canImport(UIKit)

import UIKit
import PassKit

internal class VaultCheckoutViewController: PrimerViewController {

    private var resumeHandler: ResumeHandlerProtocol!
    var subView: VaultCheckoutView = VaultCheckoutView()
    var tokenSelectedForPayment: PaymentMethodToken?

    private let loadingIndicator = UIActivityIndicatorView()
    private weak var transitionDelegate = TransitionDelegate()

    deinit {
        log(logLevel: .debug, message: "🧨 destroyed: \(self.self)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        resumeHandler = self
        
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()

        view.addSubview(subView)
        subView.delegate = self
        subView.dataSource = self
        subView.pin(to: view)
        subView.render(isBusy: true)
        viewModel.loadConfig({ [weak self] _ in
            DispatchQueue.main.async {
                guard let indicator = self?.loadingIndicator else { return }
                self?.removeLoadingView(indicator)
                self?.subView.render()
            }
        })
    }
}

extension VaultCheckoutViewController: VaultCheckoutViewDataSource {
    var selectedSavedPaymentMethod: PaymentMethodToken? {
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        return viewModel.paymentMethods.first(where: { paymentMethod in
            return paymentMethod.token == viewModel.selectedPaymentMethodId
        })
    }

    var amount: String? {
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        return viewModel.amountStringed
    }
}

// MARK: UITableView
extension VaultCheckoutViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        return viewModel.availablePaymentOptions.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    // Set the spacing between sections
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 14.0
    }

    // Make the background color show through
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = UIColor.clear // transparent
        return headerView
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        let theme: PrimerThemeProtocol = DependencyContainer.resolve()
        
        let cell = UITableViewCell(style: .default, reuseIdentifier: "cell5")

        let option = viewModel.availablePaymentOptions[indexPath.section]
        let methodView = PaymentMethodComponent(frame: view.frame, method: option)
        
        switch option.type {
        case .applePay:
            cell.accessibilityIdentifier = "payment_method_table_view_apple_pay_cell"
        case .klarna:
            cell.accessibilityIdentifier = "payment_method_table_view_klarna_cell"
        case .payPal:
            cell.accessibilityIdentifier = "payment_method_table_view_paypal_cell"
        case .goCardlessMandate:
            cell.accessibilityIdentifier = "payment_method_table_view_direct_debit_cell"
        case .paymentCard:
            cell.accessibilityIdentifier = "payment_method_table_view_card_cell"
        case .apaya:
            cell.accessibilityIdentifier = "payment_method_table_view_apaya"
        default:
            break
        }

        cell.layer.cornerRadius = 12.0
        cell.contentView.addSubview(methodView)
        methodView.pin(to: cell.contentView)
        cell.frame = cell.frame.inset(by: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        cell.backgroundColor = theme.colorTheme.main1
        cell.separatorInset = UIEdgeInsets.zero

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let router: RouterDelegate = DependencyContainer.resolve()
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        let theme: PrimerThemeProtocol = DependencyContainer.resolve()
        
        tableView.deselectRow(at: indexPath, animated: true)

        let option = viewModel.availablePaymentOptions[indexPath.section]

        switch option.type {
        case .applePay:
            let router: RouterDelegate = DependencyContainer.resolve()
            router.root?.dismiss(animated: true, completion: {
                DispatchQueue.main.async { [weak self] in
                    let appleViewModel: ApplePayViewModelProtocol = DependencyContainer.resolve()
                    appleViewModel.payWithApple { (token, err) in
                        
                    }
                }
            })
        case .paymentCard:
            router.show(.form(type: .cardForm(theme: theme)))
        case .payPal:
            router.show(.oAuth(host: .paypal))
        case .goCardlessMandate:
            router.show(.form(type: .iban(mandate: viewModel.mandate, popOnComplete: false)))
        case .klarna:
            router.show(.oAuth(host: .klarna))
        case .apaya:
            router.show(.oAuth(host: .apaya))
        default:
            break
        }
    }
}

// MARK: VaultCheckoutViewDelegate
extension VaultCheckoutViewController: VaultCheckoutViewDelegate {
    func openVault() {
        let router: RouterDelegate = DependencyContainer.resolve()
        router.show(.vaultPaymentMethods(delegate: self))
    }

    func cancel() {
        let router: RouterDelegate = DependencyContainer.resolve()
        router.pop()
    }

    func selectTokenForPayment(token: PaymentMethodToken) {
        tokenSelectedForPayment = token
    }

    func pay() {
        let router: RouterDelegate = DependencyContainer.resolve()
        let viewModel: VaultCheckoutViewModelProtocol = DependencyContainer.resolve()
        viewModel.authorizePayment({ [weak self] error in
            DispatchQueue.main.async {
                if error.exists {
                    router.show(.error(error: PrimerError.generic))
                    return
                }
                router.show(.success(type: .regular))
            }
        })
    }
}

extension VaultCheckoutViewController: ResumeHandlerProtocol {
    func handle(error: Error) {
        DispatchQueue.main.async {
            let router: RouterDelegate = DependencyContainer.resolve()
            let settings: PrimerSettingsProtocol = DependencyContainer.resolve()

            if settings.hasDisabledSuccessScreen {
                Primer.shared.dismiss()
            } else {
                router.show(.error(error: PrimerError.generic))
            }
        }
    }
    
    func handle(newClientToken clientToken: String) {
        //
    }
    
    func handleSuccess() {
        DispatchQueue.main.async {
            let router: RouterDelegate = DependencyContainer.resolve()
            let settings: PrimerSettingsProtocol = DependencyContainer.resolve()

            if settings.hasDisabledSuccessScreen {
                Primer.shared.dismiss()
            } else {
                router.show(.success(type: .regular))
            }
        }
    }
}

#endif

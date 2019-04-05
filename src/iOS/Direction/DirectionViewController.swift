//
//  DirectionViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import UIKit

@objc protocol DirectionViewControllerDelegate: class {
    func directionViewControllerDidUpdateTag(key: String, value: String?)
}

@objc class DirectionViewController: UIViewController {
    
    // MARK: Public properties
    
    @objc weak var delegate: DirectionViewControllerDelegate?
    
    // MARK: Private properties
    
    private let viewModel: MeasureDirectionViewModel
    private var disposal = Disposal()
    
    @IBOutlet weak var valueLabel: UILabel!
    @IBOutlet weak var oldValueLabel: UILabel!
    @IBOutlet weak var primaryActionButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    
    // MARK: Initializer
    
    @objc init(key: String, value: String?) {
        self.viewModel = MeasureDirectionViewModel(key: key, value: value)
        
        super.init(nibName: nil, bundle: nil)
        
        self.viewModel.delegate = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        bindToViewModel()
        
        cancelButton.addTarget(self,
                               action: #selector(cancel),
                               for: .touchUpInside)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewModel.viewDidAppear()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewModel.viewDidDisappear()
    }
    
    // MARK: Private methods
    
    @IBAction private func didTapPrimaryActionButton() {
        viewModel.didTapPrimaryActionButton()
    }
    
    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }
    
    private func bindToViewModel() {
        viewModel.valueLabelText.observe { [weak self] text, _ in
            guard let self = self else { return }
            
            self.valueLabel.text = text
            }.add(to: &self.disposal)
        
        viewModel.oldValueLabelText.observe { [weak self] text, _ in
            guard let self = self else { return }
            
            self.oldValueLabel.text = text
            }.add(to: &self.disposal)
        
        viewModel.isPrimaryActionButtonHidden.observe { [weak self] isHidden, _ in
            guard let self = self else { return }
            
            self.primaryActionButton.isHidden = isHidden
            }.add(to: &self.disposal)
        
        viewModel.dismissButtonTitle.observe { [weak self] title, _ in
            guard let self = self else { return }
            
            self.cancelButton.setTitle(title, for: .normal)
            }.add(to: &self.disposal)
    }
}

extension DirectionViewController: MeasureDirectionViewModelDelegate {
    func didFinishUpdatingTag(key: String, value: String?) {
        /// Block that is executed after the view controller was dismissed.
        let afterDismiss: (() -> Void) = { [weak self] in
            self?.delegate?.directionViewControllerDidUpdateTag(key: key, value: value)
        }
        
        if let navigationController = navigationController {
            navigationController.popViewController(animated: true)
            afterDismiss()
        } else {
            dismiss(animated: true) {
                afterDismiss()
            }
        }
    }
}


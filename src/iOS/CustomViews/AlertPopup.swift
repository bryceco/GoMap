//
//  AlertPopup.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/22/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class AlertPopup: UIViewController {
	private struct Action {
		let title: String
		let image: UIImage?
		let isCancel: Bool
		let handler: (() -> Void)?
	}

	private let titleText: String
	private let messageText: NSAttributedString
	private var actions: [Action] = []

	init(title: String, message: NSAttributedString) {
		titleText = title
		messageText = message
		super.init(nibName: nil, bundle: nil)
		modalPresentationStyle = .overFullScreen
		modalTransitionStyle = .crossDissolve
	}

	convenience init(title: String, message: String) {
		self.init(title: title, message: NSAttributedString(string: message))
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func addAction(title: String, image: UIImage? = nil, isCancel: Bool = false, handler: (() -> Void)? = nil) {
		let action = Action(title: title, image: image, isCancel: isCancel, handler: handler)
		actions.append(action)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		// dim the background screen
		view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

		// capture taps outside the alert to dismiss
		let dismissTapView = UIView()
		dismissTapView.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(dismissTapView, at: 0) // behind everything
		NSLayoutConstraint.activate([
			dismissTapView.topAnchor.constraint(equalTo: view.topAnchor),
			dismissTapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			dismissTapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			dismissTapView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
		])
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissOnBackgroundTap))
		dismissTapView.addGestureRecognizer(tapGesture)

		// set up everything else
		setupAlertView()
	}

	@objc private func dismissOnBackgroundTap() {
		dismiss(animated: true)
	}

	private func setupAlertView() {
		let buttonHeight = 55.0
		let cornerRadius = 12.0

		let textAlignment: NSTextAlignment
		if #available(iOS 26.0, *) {
			textAlignment = .natural
		} else {
			textAlignment = .center
		}

		let alertStack = UIStackView()
		alertStack.axis = .vertical
		alertStack.backgroundColor = .systemBackground
		alertStack.layer.cornerRadius = cornerRadius // should match corner radius of Cancel button
		alertStack.isLayoutMarginsRelativeArrangement = true
		if #available(iOS 26.0, *) {
			alertStack.spacing = 12
			alertStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
		} else {
			alertStack.spacing = 8
			alertStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 12, right: 20)
		}
		alertStack.translatesAutoresizingMaskIntoConstraints = false

		if #available(iOS 26.0, *) {
			let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
			let blurView = UIVisualEffectView(effect: blurEffect)
			blurView.translatesAutoresizingMaskIntoConstraints = false
			blurView.layer.cornerRadius = 20
			blurView.clipsToBounds = true
			let tintOverlay = UIView()
			tintOverlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.25)
			tintOverlay.translatesAutoresizingMaskIntoConstraints = false
			blurView.contentView.addSubview(tintOverlay)

			view.addSubview(blurView)
			tintOverlay.addSubview(alertStack)

			NSLayoutConstraint.activate([
				// make sure blur and tint are aligned
				tintOverlay.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
				tintOverlay.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
				tintOverlay.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
				tintOverlay.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
				// make sure tint and alertStack are aligned
				tintOverlay.topAnchor.constraint(equalTo: alertStack.topAnchor),
				tintOverlay.bottomAnchor.constraint(equalTo: alertStack.bottomAnchor),
				tintOverlay.leadingAnchor.constraint(equalTo: alertStack.leadingAnchor),
				tintOverlay.trailingAnchor.constraint(equalTo: alertStack.trailingAnchor)
			])

			alertStack.backgroundColor = .clear
		} else {
			view.addSubview(alertStack)
		}

		NSLayoutConstraint.activate([
			// keep everything in the safe area
			alertStack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
			alertStack.leadingAnchor.constraint(
				greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
				constant: 20),
			alertStack.trailingAnchor.constraint(
				lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
				constant: -20),
			alertStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
			// center in screen
			alertStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			alertStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			alertStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 320)
		])

		let titleLabel = UILabel()
		titleLabel.text = titleText
		titleLabel.font = UIFont.preferredFont(forTextStyle: .body).bold()
		titleLabel.textAlignment = textAlignment
		titleLabel.textColor = .label
		alertStack.addArrangedSubview(titleLabel)

		let messageLabel = UITextView()
		messageLabel.dataDetectorTypes = [.link]
		messageLabel.attributedText = messageText
		messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
		messageLabel.textColor = .label
		messageLabel.textAlignment = textAlignment
		messageLabel.backgroundColor = .clear
		messageLabel.isEditable = false
		messageLabel.isUserInteractionEnabled = true
		messageLabel.isScrollEnabled = false
		messageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
		messageLabel.textContainer.lineBreakMode = .byWordWrapping
		messageLabel.textContainer.lineFragmentPadding = 0
		alertStack.addArrangedSubview(messageLabel)

		// Cancel button with gap
		let cancelButton = ButtonClosure(type: .system)
		let title = NSLocalizedString("OK", comment: "")
		if #available(iOS 26.0, *) {
			var config = UIButton.Configuration.glass()
			config.cornerStyle = .capsule
			config.title = title
			config.background = UIBackgroundConfiguration.clear()
			config.background.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.15)
			cancelButton.configuration = config
		} else {
			// Fallback on earlier versions
			let separator = UIView()
			separator.backgroundColor = UIColor.systemGray4
			separator.heightAnchor.constraint(equalToConstant: 1.0).isActive = true
			alertStack.addArrangedSubview(separator)

			cancelButton.setTitle(title, for: .normal)
			cancelButton.tintColor = .link
			cancelButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout).bold()
			cancelButton.imageView?.contentMode = .scaleAspectFit
			cancelButton.contentHorizontalAlignment = .center
			cancelButton.semanticContentAttribute = .forceLeftToRight
			cancelButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8,
			                                            bottom: 0, right: 8)
			cancelButton.backgroundColor = .systemBackground
			cancelButton.layer.cornerRadius = cornerRadius
		}
		cancelButton.onTap = { [weak self] _ in
			self?.dismiss(animated: true)
		}
		alertStack.addArrangedSubview(cancelButton)

		NSLayoutConstraint.activate([
			cancelButton.heightAnchor.constraint(equalToConstant: buttonHeight)
		])
	}
}

//
//  MessageDisplay.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/8/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

class MessageDisplay: NSObject {
	static let shared = MessageDisplay()

	weak var flashLabel: HUDLabel! {
		didSet {
			flashLabel.font = UIFont.preferredFont(forTextStyle: .title3)
			flashLabel.layer.cornerRadius = 5
			flashLabel.layer.masksToBounds = true
			flashLabel.isHidden = true
			flashLabel.backgroundColor = .black.withAlphaComponent(0.7)
			flashLabel.textColor = .white
			flashLabel.contentInsets = .init(top: 4, left: 12, bottom: 4, right: 12)
			flashLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(flashTapped)))
			flashLabel.layer.cornerCurve = .continuous
			flashBlur.frame = flashLabel.bounds
			flashBlur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
			flashLabel.insertSubview(flashBlur, at: 0)
		}
	}

	weak var topViewController: UIViewController?
	var flashLinkConstraint: NSLayoutConstraint?

	var lastErrorDate: Date? // to prevent spamming of error dialogs
	var ignoreNetworkErrorsUntilDate: Date?
	private var flashGeneration = 0
	private var flashLink: URL?
	private lazy var flashBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))

	func showAlert(_ alert: UIAlertController) {
		topViewController?.present(alert, animated: true)
	}

	func showAlert(_ title: String, message: String?) {
		let alertError = UIAlertController(title: title,
		                                   message: message,
		                                   preferredStyle: .alert)
		alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
		showAlert(alertError)
	}

	func presentError(title: String?, error: Error, flash: Bool) {
		guard lastErrorDate == nil || Date().timeIntervalSince(lastErrorDate ?? Date()) > 3.0 else {
			return
		}
		if !flash {
			lastErrorDate = Date()
		}

		var title = title ?? NSLocalizedString("Error", comment: "")
		let defaultText = error.localizedDescription

		let isNetworkError = error is URLError
		var ignoreButton: String?

		if isNetworkError {
			if let ignoreNetworkErrorsUntilDate = ignoreNetworkErrorsUntilDate {
				if Date().timeIntervalSince(ignoreNetworkErrorsUntilDate) >= 0 {
					self.ignoreNetworkErrorsUntilDate = nil
				}
			}
			if ignoreNetworkErrorsUntilDate != nil {
				return
			}
			title = NSLocalizedString("Network error", comment: "")
			ignoreButton = NSLocalizedString("Ignore", comment: "")
		}

		// Server error responses are sometimes full HTML pages; decode asynchronously.
		let htmlMessage: String?
		if let urlError = error as? UrlSessionError,
		   case let .badStatusCode(_, message) = urlError,
		   message.prefix(1) == "<", message.suffix(1) == ">"
		{
			htmlMessage = message
		} else {
			htmlMessage = nil
		}

		Task { @MainActor in
			let text: String
			if let htmlMessage,
			   let decoded = await NSAttributedString(withHtmlString: htmlMessage)
			{
				text = decoded.string
			} else {
				text = defaultText
			}
			if flash {
				self.flashMessage(title: title, message: text)
			} else {
				let alertError = UIAlertController(title: title, message: text, preferredStyle: .alert)
				alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                   style: .cancel, handler: nil))
				if let ignoreButton = ignoreButton {
					alertError.addAction(UIAlertAction(title: ignoreButton, style: .default, handler: { [self] _ in
						// ignore network errors for a while
						ignoreNetworkErrorsUntilDate = Date().addingTimeInterval(60.0)
					}))
				}
				self.showAlert(alertError)
			}
		}
	}

	@objc private func flashTapped() {
		flashLink.map { topViewController?.present(SFSafariViewController(url: $0), animated: true) }
	}

	func flashMessage(title: String?, message: String, duration: TimeInterval = 1.0, link: URL? = nil) {
		flashLink = link
		let text = title.map { $0 + "\n\n" + message } ?? message
		let font = UIFont.preferredFont(forTextStyle: link == nil ? .title3 : .headline)
		let attributed = NSMutableAttributedString(string: link == nil ? text : " \(text) ", attributes: [
			.font: font,
			.foregroundColor: link == nil ? UIColor.white : UIColor.label
		])
		if link != nil {
			func symbol(_ name: String, _ color: UIColor) -> NSAttributedString {
				let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(font: font))
				return NSAttributedString(attachment: NSTextAttachment(image: image!.withTintColor(color, renderingMode: .alwaysOriginal)))
			}
			attributed.insert(symbol("checkmark.circle.fill", .systemGreen), at: 0)
			attributed.append(symbol("chevron.right", .tertiaryLabel))
		}
		flashBlur.isHidden = link == nil
		flashLinkConstraint?.isActive = link != nil
		flashLabel.numberOfLines = link == nil ? 0 : 1
		flashLabel.adjustsFontSizeToFitWidth = link != nil
		flashLabel.backgroundColor = link == nil ? .black.withAlphaComponent(0.7) : .clear
		flashLabel.layer.cornerRadius = link == nil ? 5 : 16
		flashLabel.contentInsets = link == nil ? .init(top: 4, left: 12, bottom: 4, right: 12)
			: .init(top: 12, left: 16, bottom: 12, right: 16)
		flashLabel.attributedText = attributed
		flashLabel.superview?.bringSubviewToFront(flashLabel)

		if flashLabel.isHidden {
			// animate in
			flashLabel.alpha = 0.0
			flashLabel.isHidden = false
			UIView.animate(withDuration: 0.25, animations: {
				self.flashLabel.alpha = 1.0
			})
		} else {
			// already displayed
			flashLabel.layer.removeAllAnimations()
			flashLabel.alpha = 1.0
		}

		flashGeneration += 1
		let generation = flashGeneration
		MainActor.runAfter(nanoseconds: UInt64(duration * 1000_000000)) {
			guard self.flashGeneration == generation else { return }
			UIView.animate(withDuration: 0.35, animations: {
				self.flashLabel.alpha = 0.0
			}) { finished in
				if finished, self.flashLabel.layer.presentation()?.opacity == 0.0 {
					self.flashLabel.isHidden = true
				}
			}
		}
	}

	func showInternalError(_ error: Error, context: String?) {
		Task { @MainActor in
			let message = """
			\(String(describing: error))
			\(context ?? "")

			Please send a screen shot of this message to the developer
			"""
			showAlert("Internal error", message: message)
		}
	}
}

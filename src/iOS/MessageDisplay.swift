//
//  MessageDisplay.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/8/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

class MessageDisplay {
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
		}
	}

	weak var topViewController: UIViewController?

	var lastErrorDate: Date? // to prevent spamming of error dialogs
	var ignoreNetworkErrorsUntilDate: Date?
	private var flashGeneration = 0

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
		defer {
			if !flash {
				lastErrorDate = Date()
			}
		}
		guard lastErrorDate == nil || Date().timeIntervalSince(lastErrorDate ?? Date()) > 3.0 else {
			return
		}

		var title = title ?? NSLocalizedString("Error", comment: "")
		var text = error.localizedDescription

		var isNetworkError = false
		var ignoreButton: String?
		let userInfo = (error as NSError).userInfo
		if userInfo["NSErrorFailingURLKey"] != nil {
			isNetworkError = true
		}
		if let underError = userInfo["NSUnderlyingError"] as? NSError,
		   (underError.domain as CFString) == kCFErrorDomainCFNetwork
		{
			isNetworkError = true
		}

		// Decode HTML text
		if let error = error as? UrlSessionError,
		   case let .badStatusCode(_, message) = error,
		   message.prefix(1) == "<", message.suffix(1) == ">",
		   let html = NSAttributedString(withHtmlString: message)
		{
			text = html.string
		}

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

		if flash {
			flashMessage(title: title, message: text)
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
			showAlert(alertError)
		}
	}

	func flashMessage(title: String?, message: String, duration: TimeInterval = 1.0) {
		flashLabel.text = title.map { $0 + "\n\n" + message } ?? message
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

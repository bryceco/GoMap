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

	weak var flashLabel: UILabel! {
		didSet {
			flashLabel.font = UIFont.preferredFont(forTextStyle: .title3)
			flashLabel.layer.cornerRadius = 5
			flashLabel.layer.masksToBounds = true
			flashLabel.isHidden = true
		}
	}

	weak var topViewController: UIViewController?

	var lastErrorDate: Date? // to prevent spamming of error dialogs
	var ignoreNetworkErrorsUntilDate: Date?

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
		if lastErrorDate == nil || Date().timeIntervalSince(lastErrorDate ?? Date()) > 3.0 {
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
			if let error = error as? UrlSessionError,
			   case let .badStatusCode(_, html) = error,
			   html.count > 20
			{
				text = html
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
				flashMessage(title: title, message: text, duration: 0.9)
			} else {
				let alertError = UIAlertController(title: title, message: text, preferredStyle: .alert)
				if let attrText = NSMutableAttributedString(withHtmlString: text,
				                                            textColor: UIColor.black,
				                                            backgroundColor: UIColor.white)
				{
					alertError.setValue(attrText, forKey: "attributedMessage")
				}
				alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                   style: .cancel, handler: nil))
				if let ignoreButton = ignoreButton {
					alertError.addAction(UIAlertAction(title: ignoreButton, style: .default, handler: { [self] _ in
						// ignore network errors for a while
						ignoreNetworkErrorsUntilDate = Date().addingTimeInterval(5 * 60.0)
					}))
				}
				showAlert(alertError)
			}
		}
		if !flash {
			lastErrorDate = Date()
		}
	}

	func flashMessage(title: String?, message: String, duration: TimeInterval = 0.7) {
		let MAX_ALPHA: CGFloat = 0.8

		if let attrText = NSMutableAttributedString(withHtmlString: message,
		                                            textColor: UIColor.white,
		                                            backgroundColor: UIColor.black),
			attrText.length > 0
		{
			if let title = title {
				let attrTitle = NSMutableAttributedString(string: title + "\n\n", attributes: [
					.foregroundColor: UIColor.white,
					.backgroundColor: UIColor.black
				])
				attrTitle.append(attrText)
				flashLabel.attributedText = attrTitle
			} else {
				flashLabel.attributedText = attrText
			}
		} else {
			if let title = title {
				flashLabel.text = title + "\n\n" + message
			} else {
				flashLabel.text = message
			}
		}

		if flashLabel.isHidden {
			// animate in
			flashLabel.alpha = 0.0
			flashLabel.isHidden = false
			UIView.animate(withDuration: 0.25, animations: {
				self.flashLabel.alpha = MAX_ALPHA
			})
		} else {
			// already displayed
			flashLabel.layer.removeAllAnimations()
			flashLabel.alpha = MAX_ALPHA
		}

		MainActor.runAfter(nanoseconds: UInt64(duration * 1000_000000)) {
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

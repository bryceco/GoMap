//
//  KeyboardToolbar.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/6/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

/// A general-purpose keyboard input-accessory toolbar built from a list of items.
/// Items can be titled buttons, SF Symbol icon buttons, or spacers.
/// Uses UIInputView so its background automatically matches the keyboard chrome
/// (light gray in light mode, charcoal in dark mode).
class KeyboardToolbar: UIInputView {

	struct Item {
		fileprivate enum Kind {
			case title(String)
			case icon(String)        // SF Symbol name
			case image(UIImage)      // arbitrary UIImage
			case done                // checkmark on iOS 26+, "Done" text on earlier versions
			case flexibleSpace
			case fixedSpace(CGFloat)
		}

		fileprivate let kind: Kind
		fileprivate let action: ((UIButton) -> Void)?

		static func title(_ string: String, action: @escaping (UIButton) -> Void) -> Item {
			Item(kind: .title(string), action: action)
		}

		static func icon(_ symbolName: String, action: @escaping (UIButton) -> Void) -> Item {
			Item(kind: .icon(symbolName), action: action)
		}

		static func image(_ image: UIImage, action: @escaping (UIButton) -> Void) -> Item {
			Item(kind: .image(image), action: action)
		}

		static func done(action: @escaping (UIButton) -> Void) -> Item {
			Item(kind: .done, action: action)
		}

		static let flexibleSpace = Item(kind: .flexibleSpace, action: nil)

		static func fixedSpace(_ width: CGFloat) -> Item {
			Item(kind: .fixedSpace(width), action: nil)
		}
	}

	init(items: [Item]) {
		super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44),
				   inputViewStyle: .keyboard)

		// Set up background view we place buttons into
		let blurView = UIVisualEffectView(effect: nil)
		blurView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(blurView)
		NSLayoutConstraint.activate([
			blurView.topAnchor.constraint(equalTo: topAnchor),
			blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
			blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
			blurView.trailingAnchor.constraint(equalTo: trailingAnchor)
		])

		if #available(iOS 26, *) {
			// When using glass the background is transparent, which doesn't look good,
			// so we add our own semi-opaque blurry background.
			blurView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
			// When in dark mode the background should be darker to match the keyboard background
			blurView.contentView.backgroundColor = UIColor { trait in
				trait.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.5) : .clear
			}

			let cornerRadius: CGFloat = 16
			layer.cornerRadius = cornerRadius
			clipsToBounds = true
			blurView.layer.cornerRadius = cornerRadius
			blurView.clipsToBounds = true
		} else {
			// on older versions our UIInputView superclass provides a background that matches the keyboard
		}

		let stack = UIStackView(arrangedSubviews: items.map(Self.makeView(for:)))
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 10
		stack.translatesAutoresizingMaskIntoConstraints = false

		blurView.contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
			stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 8),
			stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -8)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private static func makeView(for item: Item) -> UIView {
		switch item.kind {
		case .title, .icon, .image, .done:
			return makeButton(for: item)
		case .flexibleSpace:
			let spacer = UIView()
			spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
			return spacer
		case .fixedSpace(let width):
			let spacer = UIView()
			spacer.translatesAutoresizingMaskIntoConstraints = false
			spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
			return spacer
		}
	}

	static let buttonBackgroundColor: UIColor = UIColor { trait in
		switch trait.userInterfaceStyle {
		case .dark:
			if #available(iOS 26, *) {
				return UIColor(red: 61.0 / 255.0, green: 61.0 / 255.0, blue: 62.0 / 255.0, alpha: 1.0)
			} else {
				return UIColor(red: 108.0 / 255.0, green: 108.0 / 255.0, blue: 109.0 / 255.0, alpha: 1.0)
			}
		default:
			return .white
		}
	}

	private static func makeButton(for item: Item) -> ButtonClosure {
		let button = ButtonClosure(type: .custom)
		button.onTap = item.action

		if case .done = item.kind {
			if #available(iOS 15, *) {
				var config = UIButton.Configuration.filled()
				if #available(iOS 26, *) {
					config.image = UIImage(systemName: "checkmark")
				} else {
					config.title = NSLocalizedString("Done", comment: "")
				}
				config.baseBackgroundColor = .systemBlue
				config.baseForegroundColor = .white
				button.configuration = config
			} else {
				button.setTitle(NSLocalizedString("Done", comment: ""), for: .normal)
				button.setTitleColor(.white, for: .normal)
				button.backgroundColor = .systemBlue
				button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
				button.layer.cornerRadius = 10
			}
		} else {
			switch item.kind {
			case .title(let string):
				button.setTitle(string, for: .normal)
				button.setTitleColor(.label, for: .normal)
			case .icon(let name):
				button.setImage(UIImage(systemName: name), for: .normal)
				button.tintColor = .systemBlue
			case .image(let img):
				button.setImage(img, for: .normal)
				button.tintColor = .systemBlue
			default:
				break
			}
			button.backgroundColor = Self.buttonBackgroundColor
			button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
			button.layer.borderWidth = 1
			button.layer.cornerRadius = 10
			button.layer.borderColor = UIColor.clear.cgColor
		}
		return button
	}
}

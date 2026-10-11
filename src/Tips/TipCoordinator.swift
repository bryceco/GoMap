import SwiftUI
import TipKit
import UIKit

// MARK: - Tip definition

@available(iOS 17.0, *)
struct AppTip: Tip {
	let id: String
	let title: Text
	let message: Text?
	let image: Image?
	let rules: [Rule]

	var options: [TipOption] { [Tips.MaxDisplayCount(1)] }

	init(title: String, message: String, image: Image? = nil, rules: [Rule] = []) {
		self.id = title
		self.title = Text(title)
		self.message = Text(message)
		self.image = image
		self.rules = rules
	}
}

// MARK: - Catalog

@available(iOS 17.0, *)
enum AppTips {
	static let location = AppTip(title: "Re-center the map",
	                             message: "Tap once to jump to your location and again to follow your heading.",
	                             image: Image(systemName: "location"))
	static let orientation = AppTip(title: "Stay oriented",
	                                message: "Use the compass to switch between north-up and heading-up views.",
	                                image: Image(uiImage: UIImage(named: "temaki-compass")!.withRenderingMode(.alwaysTemplate)))
	static let search = AppTip(title: "Find places quickly",
	                           message: "Search for addresses, places, and presets without leaving the map.",
	                           image: Image(systemName: "magnifyingglass"))
	static let mapLayers = AppTip(title: "Switch map layers",
	                              message: "Tap for display options or long-press to pick recent imagery.",
	                              image: Image(systemName: "map"))
	static let addButton = AppTip(title: "Add features faster",
	                              message: "Tap to add at the crosshairs or drag and long-press for precise placement.",
	                              image: Image(systemName: "plus"))
	static let gpxTraces = AppTip(title: "Record GPX traces",
	                              message: "Keep the switch on to capture or review your GPS tracks while you map.")
	static let quests = AppTip(title: "Tackle quests",
	                           message: "Show quests to discover nearby tasks contributed by the community.")
	static let dataLayers = AppTip(title: "Overlay more data",
	                               message: "Enable data layers to compare third-party maps and QA overlays while editing.")
	static let alternateServer = AppTip(title: "Map beyond OSM",
	                                    message: "Pick OpenHistoricalMap or OpenGeofiction to contribute to other communities.")
}

// MARK: - Configuration

func configureTipsIfNeeded() {
	guard #available(iOS 17.0, *) else { return }
	do {
#if DEBUG
		try? Tips.resetDatastore()
#endif
		try Tips.configure([
			.displayFrequency(.immediate)
		])
	} catch {
		print("[TipKit] configuration failed: \(error)")
	}
}

// MARK: - Presentation

@available(iOS 17.0, *)
extension UIViewController {
	/// Present each eligible tip in order, waiting for dismissal between them.
	func showTips(_ tips: [(any Tip, UIView?)]) {
		Task { @MainActor in
			for (tip, view) in tips {
				guard let view, view.window != nil else { continue }

				// Wait for tip to become eligible (data store loads async).
				// If the tip is invalidated the sequence completes and we skip it.
				for await shouldDisplay in tip.shouldDisplayUpdates {
					guard shouldDisplay else { continue }
					break
				}
				guard tip.shouldDisplay else { continue }

				// Wait for any previous popover to be dismissed.
				while view.isHidden || presentedViewController != nil {
					try? await Task.sleep(for: .milliseconds(200))
				}

				let anchor = tipAnchor(for: view)
				let popover = TipUIPopoverViewController(tip, sourceItem: view)
				popover.popoverPresentationController?.sourceRect = anchor.rect
				popover.popoverPresentationController?.permittedArrowDirections = anchor.arrow
				present(popover, animated: true)
			}
		}
	}
}

@available(iOS 17.0, *)
extension UIViewController {
	/// Anchor on the edge of `view` that faces away from the nearest screen edge,
	/// and force the matching arrow, so the arrow touches the button's border.
	private func tipAnchor(for view: UIView) -> (rect: CGRect, arrow: UIPopoverArrowDirection) {
		let f = view.convert(view.bounds, to: self.view)
		let b = view.bounds
		if f.midY > self.view.bounds.midY {
			// lower half of screen: popover above, arrow touches the top edge
			return (CGRect(x: b.minX, y: b.minY, width: b.width, height: 1), .down)
		} else {
			// upper half: popover below, arrow touches the bottom edge
			return (CGRect(x: b.minX, y: b.maxY - 1, width: b.width, height: 1), .up)
		}
	}
}

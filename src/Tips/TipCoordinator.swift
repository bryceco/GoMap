import SwiftUI
import TipKit
import UIKit

// MARK: - Tip definition

/// Generic tip whose phantom `Tag` type gives each specialisation a unique
/// identity in TipKit's data store.
@available(iOS 17.0, *)
struct AppTip<Tag>: Tip {
	let title: Text
	let message: Text?
	let image: Image?

	var options: [TipOption] { [Tips.MaxDisplayCount(1)] }

	init(_ title: String, _ message: String, symbol: String) {
		self.title = Text(title)
		self.message = Text(message)
		self.image = Image(systemName: symbol)
	}
}

// MARK: - Catalog

@available(iOS 17.0, *)
enum AppTips {
	// Phantom tag types — each makes AppTip<T> a distinct Tip for TipKit.
	enum Location {}
	enum Orientation {}
	enum Search {}
	enum MapLayers {}
	enum AddButton {}
	enum GpxTraces {}
	enum Quests {}
	enum DataLayers {}
	enum AlternateServer {}

	static let location = AppTip<Location>(
		"Re-center the map",
		"Tap once to jump to your location and again to follow your heading.",
		symbol: "location.circle")
	static let orientation = AppTip<Orientation>(
		"Stay oriented",
		"Use the compass to switch between north-up and heading-up views.",
		symbol: "location.north.line")
	static let search = AppTip<Search>(
		"Find places quickly",
		"Search for addresses, places, and presets without leaving the map.",
		symbol: "magnifyingglass")
	static let mapLayers = AppTip<MapLayers>(
		"Switch map layers",
		"Tap for display options or long-press to pick recent imagery.",
		symbol: "square.stack.3d.up")
	static let addButton = AppTip<AddButton>(
		"Add features faster",
		"Tap to add at the crosshairs or drag and long-press for precise placement.",
		symbol: "plus.circle")
	static let gpxTraces = AppTip<GpxTraces>(
		"Record GPX traces",
		"Keep the switch on to capture or review your GPS tracks while you map.",
		symbol: "map")
	static let quests = AppTip<Quests>(
		"Tackle quests",
		"Show quests to discover nearby tasks contributed by the community.",
		symbol: "flag")
	static let dataLayers = AppTip<DataLayers>(
		"Overlay more data",
		"Enable data layers to compare third-party maps and QA overlays while editing.",
		symbol: "square.grid.3x2")
	static let alternateServer = AppTip<AlternateServer>(
		"Map beyond OSM",
		"Pick OpenHistoricalMap or OpenGeofiction to contribute to other communities.",
		symbol: "globe")
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
				while presentedViewController != nil {
					try? await Task.sleep(for: .milliseconds(200))
				}
				// Anchor at the view's inner edge so the arrow points to the
				// border rather than the center of the button.
				let guide = UILayoutGuide()
				view.addLayoutGuide(guide)
				let onRight = view.frame.midX > (view.superview?.bounds.midX ?? 0)
				NSLayoutConstraint.activate([
					guide.topAnchor.constraint(equalTo: view.topAnchor),
					guide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
					guide.widthAnchor.constraint(equalToConstant: 1),
					onRight
						? guide.leadingAnchor.constraint(equalTo: view.leadingAnchor)
						: guide.trailingAnchor.constraint(equalTo: view.trailingAnchor)
				])
				view.layoutIfNeeded()
				present(TipUIPopoverViewController(tip, sourceItem: guide), animated: true)
			}
		}
	}
}

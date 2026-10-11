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
	/// Present the first eligible tip from the list. One tip per appearance.
	func showFirstTip(_ tips: [(any Tip, UIView?)]) {
		Task { @MainActor in
			// TipKit's data store loads asynchronously after Tips.configure().
			// shouldDisplayUpdates emits false during loading, then true once ready.
			for (tip, view) in tips {
				guard let view, view.window != nil else { continue }
				for await shouldDisplay in tip.shouldDisplayUpdates {
					guard shouldDisplay else { continue }
					guard presentedViewController == nil else { return }
					present(TipUIPopoverViewController(tip, sourceItem: view), animated: true)
					return
				}
			}
		}
	}
}

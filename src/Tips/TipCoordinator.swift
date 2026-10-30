import SwiftUI
import TipKit
import UIKit

// MARK: - State

@available(iOS 17.0, *)
enum TipState {
	/// What the user currently has selected, for tips that only make sense
	/// in a particular situation. Updated from MapView.updateEditControl().
	@Parameter(.transient) static var hasPushpin: Bool = false
	/// 0 when no way is selected
	@Parameter(.transient) static var selectedWayNodeCount: Int = 0
	@Parameter(.transient) static var selectedWayIsClosed: Bool = false
}

/// Record that the user performed the action a tip describes, so it is never shown.
func tipActionPerformed(_ id: TipID) {
	if #available(iOS 17.0, *) {
		AppTips.tip(id).invalidate(reason: .actionPerformed)
	}
}

/// Update selection state used by tip rules.
func tipSelectionChanged(hasPushpin: Bool, selection: OsmBaseObject?) {
	guard #available(iOS 17.0, *) else { return }
	let way = selection as? OsmWay
	TipState.hasPushpin = hasPushpin
	TipState.selectedWayNodeCount = way?.nodes.count ?? 0
	TipState.selectedWayIsClosed = way?.isClosed() ?? false
}

// MARK: - Tip definition

/// Identifier for every tip in the app. Not availability-gated so call sites
/// that invalidate tips don't need `#available` checks.
enum TipID: String, CaseIterable {
	// Onboarding, in order
	case location, dropNode, editTags, upload
	case extendToWay, closeWayByDrag, makeRectangular
	// Main map
	case orientation, search, mapLayers
	case holdAndTap, doubleTapDragZoom, overlappingObjects, plusButtonSide
	// Editing
	case closeWay, circularize, turnRestrictions, copyPasteTags
	case compassDirection, buildingHeight, openingHoursCamera, wikiInfo
	// Display settings
	case gpxTraces, quests, questBuilder, dataLayers, notesAndFixme, imageryOffset
	// Settings / data
	case customFeatures, customFields, filesApp, searchCoordinates, clearCache, alternateServer
}

@available(iOS 17.0, *)
struct AppTip: Tip {
	let id: String
	let title: Text
	let message: Text?
	let image: Image?
	let rules: [Rule]
	/// False while the tip exists only in the catalog and no screen presents it yet.
	let implemented: Bool

	var options: [TipOption] { [Tips.MaxDisplayCount(1)] }

	init(_ id: TipID, title: String, message: String, image: Image? = nil, rules: [Rule] = [],
	     implemented: Bool = false)
	{
		self.id = id.rawValue
		self.title = Text(title)
		self.message = Text(message)
		self.image = image
		self.rules = rules
		self.implemented = implemented
	}
}

// MARK: - Catalog

@available(iOS 17.0, *)
enum AppTips {
	// Onboarding
	static let location = AppTip(.location, title: "Find yourself",
	                             message: "Tap to jump to your current location. Tap again to follow your heading.",
	                             image: Image(systemName: "location"),
	                             implemented: true)
	static let dropNode = AppTip(.dropNode, title: "Add something",
	                             message: "Tap + to drop a point at the crosshairs.",
	                             image: Image(systemName: "plus"),
	                             implemented: true)
	static let editTags = AppTip(.editTags, title: "Say what it is",
	                             message: "Tap Tags to choose a feature type and fill in details.",
	                             image: Image(systemName: "tag"),
	                             implemented: true)
	static let upload = AppTip(.upload, title: "Share your work",
	                           message: "Tap Upload to send your edits to OpenStreetMap.",
	                           image: Image(systemName: "icloud.and.arrow.up"),
	                           implemented: true)
	static let extendToWay = AppTip(.extendToWay, title: "Draw a line",
	                                message: "With a point selected, tap + again to extend it into a way.",
	                                image: Image(systemName: "scribble"),
	                                rules: [#Rule(TipState.$hasPushpin) { $0 == true },
	                                        #Rule(TipState.$selectedWayNodeCount) { $0 == 0 }],
	                                implemented: true)
	static let closeWayByDrag = AppTip(.closeWayByDrag, title: "Close the loop",
	                                   message: "Drag the last point onto the first to make a closed area.",
	                                   image: Image(systemName: "arrow.triangle.capsulepath"),
	                                   rules: [#Rule(TipState.$selectedWayIsClosed) { $0 == false },
	                                           #Rule(TipState.$selectedWayNodeCount) { $0 >= 4 }],
	                                   implemented: true)
	static let makeRectangular = AppTip(.makeRectangular, title: "Square it up",
	                                    message: "Choose More… then Make Rectangular to straighten the corners.",
	                                    image: Image(systemName: "square"),
	                                    rules: [#Rule(TipState.$selectedWayIsClosed) { $0 == true }],
	                                    implemented: true)

	// Main map
	static let orientation = AppTip(.orientation, title: "Stay oriented",
	                                message: "Use the compass to switch between north-up and heading-up views.",
	                                image: Image(uiImage: UIImage(named: "temaki-compass")!.withRenderingMode(.alwaysTemplate)),
	                                implemented: true)
	static let search = AppTip(.search, title: "Find places quickly",
	                           message: "Search for addresses, places, and presets without leaving the map.",
	                           image: Image(systemName: "magnifyingglass"), implemented: true)
	static let mapLayers = AppTip(.mapLayers, title: "Switch map layers",
	                              message: "Tap for display options or long-press to pick recent imagery.",
	                              image: Image(systemName: "map"), implemented: true)
	static let holdAndTap = AppTip(.holdAndTap, title: "Add points faster",
	                               message: "Hold the + button and tap the map to add several points without lifting your finger.",
	                               image: Image(systemName: "hand.tap"))
	static let doubleTapDragZoom = AppTip(.doubleTapDragZoom, title: "Zoom with one finger",
	                                      message: "Double-tap and drag up or down to zoom without pinching.",
	                                      image: Image(systemName: "plus.magnifyingglass"))
	static let overlappingObjects = AppTip(.overlappingObjects, title: "Pick from overlapping objects",
	                                       message: "Long-press the map to get a menu of everything under your finger.",
	                                       image: Image(systemName: "square.3.layers.3d"))
	static let plusButtonSide = AppTip(.plusButtonSide, title: "Left-handed?",
	                                   message: "You can move the + button to the other side of the screen in Display settings.",
	                                   image: Image(systemName: "arrow.left.arrow.right"))

	// Editing
	static let closeWay = AppTip(.closeWay, title: "Close this way",
	                             message: "Areas like buildings need a closed outline. Use Close Way from the edit menu.",
	                             image: Image(systemName: "arrow.triangle.capsulepath"))
	static let circularize = AppTip(.circularize,
	                                title: "Make it round",
	                                message: "Choose More… then Make Circular. Pick the number of points to get an octagon or other polygon instead.",
	                                image: Image(systemName: "circle"))
	static let turnRestrictions = AppTip(.turnRestrictions, title: "Edit turn restrictions",
	                                     message: "Select a node shared by two roads and choose Restrict from the edit menu.",
	                                     image: Image(systemName: "arrow.turn.up.right"))
	static let copyPasteTags = AppTip(.copyPasteTags,
	                                  title: "Copy and paste tags",
	                                  message: "Copy tags from one object and paste them onto another. Paste also accepts text from any app, one key=value per line.",
	                                  image: Image(systemName: "doc.on.doc"))
	static let compassDirection = AppTip(.compassDirection,
	                                     title: "Set direction with the compass",
	                                     message: "Tap the compass next to the Direction field and point your phone the way the feature faces.",
	                                     image: Image(systemName: "location.north.line"))
	static let buildingHeight = AppTip(.buildingHeight, title: "Measure height with the camera",
	                                   message: "Tap the ruler next to the Height field to measure a building with your camera.",
	                                   image: Image(systemName: "ruler"))
	static let openingHoursCamera = AppTip(.openingHoursCamera, title: "Read hours from a sign",
	                                       message: "Point the camera at an opening-hours sign and the text is recognized for you.",
	                                       image: Image(systemName: "camera.viewfinder"))
	static let wikiInfo = AppTip(.wikiInfo, title: "Look up a tag",
	                             message: "Tap the info button next to any tag to open its OpenStreetMap wiki page.",
	                             image: Image(systemName: "info.circle"))

	// Display settings
	static let gpxTraces = AppTip(.gpxTraces,
	                              title: "Record GPX traces",
	                              message: "Keep the switch on to capture tracks in the background, or import a GPX via Files or the share sheet.",
	                              implemented: true)
	static let quests = AppTip(.quests, title: "Tackle quests",
	                           message: "Show quests to discover nearby tasks contributed by the community.",
	                           implemented: true)
	static let questBuilder = AppTip(.questBuilder, title: "Build your own quests",
	                                 message: "The quest builder lets you define custom quests for the tags you care about.")
	static let dataLayers = AppTip(.dataLayers, title: "Overlay more data",
	                               message: "Enable data layers to compare third-party maps and QA overlays while editing.",
	                               implemented: true)
	static let notesAndFixme = AppTip(.notesAndFixme, title: "See notes and fixme markers",
	                                  message: "Turn on Notes to show OSM notes and fixme tags on the map.",
	                                  image: Image(systemName: "note.text"))
	static let imageryOffset = AppTip(.imageryOffset, title: "Fix misaligned imagery",
	                                  message: "Use the imagery offset button to nudge aerial imagery into alignment with GPS traces.",
	                                  image: Image(systemName: "arrow.up.and.down.and.arrow.left.and.right"))

	// Settings / data
	static let customFeatures = AppTip(.customFeatures, title: "Create custom features",
	                                   message: "Define your own presets in Settings when the built-in ones don't fit.")
	static let customFields = AppTip(.customFields, title: "Create custom fields",
	                                 message: "Add fields for tags you use often so they appear in the editor.")
	static let filesApp = AppTip(.filesApp, title: "Find app data in Files",
	                             message: "Your GPX traces, GeoJSON and custom presets live in the Files app under Go Map!!.",
	                             image: Image(systemName: "folder"))
	static let searchCoordinates = AppTip(.searchCoordinates, title: "Search by coordinates or URL",
	                                      message: "Type latitude, longitude or paste an OSM URL to jump straight there.",
	                                      image: Image(systemName: "mappin.and.ellipse"))
	static let clearCache = AppTip(.clearCache, title: "Data looking stale?",
	                               message: "Clear the cache in Settings to re-download the current area.",
	                               image: Image(systemName: "arrow.clockwise"))
	static let alternateServer = AppTip(.alternateServer, title: "Map beyond OSM",
	                                    message: "Pick OpenHistoricalMap or OpenGeofiction to contribute to other communities.",
	                                    implemented: true)

	/// Exhaustive so the compiler flags a TipID with no catalog entry.
	static func tip(_ id: TipID) -> AppTip {
		switch id {
		case .location: return location
		case .dropNode: return dropNode
		case .editTags: return editTags
		case .upload: return upload
		case .extendToWay: return extendToWay
		case .closeWayByDrag: return closeWayByDrag
		case .makeRectangular: return makeRectangular
		case .orientation: return orientation
		case .search: return search
		case .mapLayers: return mapLayers
		case .holdAndTap: return holdAndTap
		case .doubleTapDragZoom: return doubleTapDragZoom
		case .overlappingObjects: return overlappingObjects
		case .plusButtonSide: return plusButtonSide
		case .closeWay: return closeWay
		case .circularize: return circularize
		case .turnRestrictions: return turnRestrictions
		case .copyPasteTags: return copyPasteTags
		case .compassDirection: return compassDirection
		case .buildingHeight: return buildingHeight
		case .openingHoursCamera: return openingHoursCamera
		case .wikiInfo: return wikiInfo
		case .gpxTraces: return gpxTraces
		case .quests: return quests
		case .questBuilder: return questBuilder
		case .dataLayers: return dataLayers
		case .notesAndFixme: return notesAndFixme
		case .imageryOffset: return imageryOffset
		case .customFeatures: return customFeatures
		case .customFields: return customFields
		case .filesApp: return filesApp
		case .searchCoordinates: return searchCoordinates
		case .clearCache: return clearCache
		case .alternateServer: return alternateServer
		}
	}

	/// Every tip, in TipID order.
	static let all: [AppTip] = TipID.allCases.map(tip)
}

// MARK: - Configuration

func configureTips() {
	guard #available(iOS 17.0, *) else { return }
	do {
		try Tips.configure([
			.displayFrequency(.immediate)
		])
#if DEBUG
		debugPrintTipStatus()
#endif
	} catch {
		print("[TipKit] configuration failed: \(error)")
	}
}

#if DEBUG
/// Print every tip and whether it has been implemented and whether the user
/// has already performed the action it describes. For testing only.
@available(iOS 17.0, *)
private func debugPrintTipStatus() {
	Task { @MainActor in
		// the datastore loads asynchronously
		try? await Task.sleep(for: .seconds(1))
		for tip in AppTips.all {
			let status: String
			switch tip.status {
			case .pending:
				status = "not eligible"
			case .available:
				status = "ready"
			case .invalidated(let x):
				status = "perfomed: \(x)"
			@unknown default:
				fatalError()
			}
			print("[TipKit] \(tip.id): implemented=\(tip.implemented ? "yes" : "no") status=\(status)")
		}
	}
}
#endif

// MARK: - Presentation

@available(iOS 17.0, *)
extension UIViewController {
	/// Present each eligible tip, waiting for dismissal between them. Each tip
	/// waits independently for its rules to be satisfied and its anchor to be
	/// visible, so a tip that never becomes eligible doesn't block the ones
	/// after it, and situational tips can appear long after the screen was shown.
	@MainActor func showTips(_ tips: [(any Tip, UIView?)]) {
		for (tip, view) in tips {
			guard let view, view.window != nil else { continue }
			// a screen may call this on every viewDidAppear; don't wait twice for the same tip
			guard !tipsBeingWaitedOn.contains(tip.id) else { continue }
			tipsBeingWaitedOn.insert(tip.id)

			Task { @MainActor in
				defer { tipsBeingWaitedOn.remove(tip.id) }

				// Wait for tip to become eligible (data store loads async, rules may be met later).
				// If the tip is invalidated the sequence completes and we skip it.
				for await shouldDisplay in tip.shouldDisplayUpdates {
					guard shouldDisplay else { continue }
					break
				}
				guard tip.shouldDisplay else { return }

				// Wait for the anchor to be visible and any previous popover to be dismissed.
				while view.isHidden || view.window == nil || presentedViewController != nil {
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

@MainActor private var tipsBeingWaitedOn = Set<String>()

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

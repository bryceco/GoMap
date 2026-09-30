//
//  GlobeBasemapView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/30/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import GlobeRenderer
import UIKit

/// Hosts a GlobeRenderer `GlobeView` as a background layer of `MapLayersView`.
///
/// When zoomed out far enough that the earth's curvature is visible this replaces
/// the flat aerial or basemap tile layer, reusing that layer's imagery and tile cache.
/// GoMap continues to own all gestures: the globe camera is driven from the shared
/// map transform so the two stay in lock-step and the handoff between them is seamless.
@MainActor
final class GlobeBasemapView: UIView {
	private let viewPort: MapViewPort
	private let globeView: GlobeView
	private var tileSource: TileServerGlobeSource?

	/// Narrower than the package default of 60° so the camera sits farther from the
	/// surface: this reduces perspective foreshortening toward the screen edges and
	/// makes the globe match the flat map more closely at the moment of handoff.
	private static let fieldOfView: CGFloat = 30

	private static let fadeDuration = 0.4
	/// Maximum time to wait for the globe's initial tiles before fading it in anyway.
	private static let maxTileWait = 1.0

	/// Incremented on every fadeIn/fadeOut so stale completions can be ignored.
	private var transitionID = 0
	/// Invoked from the globe's render callback once no tile downloads remain.
	private var tilesReadyHandler: (() -> Void)?

	init(viewPort: MapViewPort) {
		self.viewPort = viewPort
		globeView = GlobeView(frame: .zero) // no imagery until configure(from:) is called
		super.init(frame: .zero)

		globeView.gesturesEnabled = false
		globeView.lockNorth = true
		globeView.showsDownloadIndicator = false
		globeView.showsCoordinateLabel = false
		globeView.fieldOfView = Self.fieldOfView
		globeView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
		globeView.onRender = { [weak self] pendingDownloads in
			guard let self,
			      pendingDownloads == 0,
			      let handler = self.tilesReadyHandler
			else { return }
			self.tilesReadyHandler = nil
			handler()
		}
		addSubview(globeView)

		// Touches pass through to the gesture recognizers owned by MainViewController
		isUserInteractionEnabled = false

		viewPort.mapTransform.onChange.subscribe(self) { [weak self] in
			self?.updateCamera()
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError()
	}

	/// The imagery currently displayed on the globe.
	var tileServer: TileServer? { tileSource?.cache.tileServer }

	/// Display the same imagery as `layer`, sharing its tile cache.
	func configure(from layer: MercatorTileLayer) {
		guard let cache = layer.tileCache,
		      cache !== tileSource?.cache
		else { return }
		let source = TileServerGlobeSource(cache: cache)
		tileSource = source
		globeView.tileSource = source
	}

	/// Discard loaded textures so they are regenerated for the current appearance.
	func updateDarkMode() {
		if let tileSource {
			globeView.tileSource = tileSource
		}
	}

	// MARK: Fading

	/// True once the globe is visible and fully opaque.
	var isFullyVisible: Bool {
		return !isHidden && alpha == 1.0
	}

	/// Reveal the globe over the flat map. It is made visible immediately at zero alpha
	/// so it starts rendering and loading tiles, then fades in once the visible tiles
	/// are textured (or after a short timeout), so the user never sees placeholders.
	/// `completion` is called only if the fade ran to completion.
	func fadeIn(completion: @escaping () -> Void) {
		transitionID += 1
		let id = transitionID

		if isHidden {
			// not quite zero, to be sure Core Animation still asks the SceneKit view to draw
			alpha = 0.01
			isHidden = false
		}
		if alpha == 1.0 {
			completion()
			return
		}

		waitForTiles { [weak self] in
			guard let self, self.transitionID == id else { return }
			UIView.animate(withDuration: Self.fadeDuration, animations: {
				self.alpha = 1.0
			}, completion: { finished in
				if finished, self.transitionID == id {
					completion()
				}
			})
		}
	}

	/// Fade the globe out, revealing the flat map underneath, then hide it.
	func fadeOut() {
		transitionID += 1
		let id = transitionID
		tilesReadyHandler = nil

		guard !isHidden else { return }
		UIView.animate(withDuration: Self.fadeDuration, animations: {
			self.alpha = 0.0
		}, completion: { [weak self] finished in
			guard let self, finished, self.transitionID == id else { return }
			self.isHidden = true
		})
	}

	private func waitForTiles(then handler: @escaping () -> Void) {
		tilesReadyHandler = handler
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxTileWait) { [weak self] in
			guard let self, let handler = self.tilesReadyHandler else { return }
			self.tilesReadyHandler = nil
			handler()
		}
	}

	// MARK: Layout & camera

	override var isHidden: Bool {
		didSet {
			// stops rendering while hidden, and requests a frame when shown
			globeView.isHidden = isHidden
			if !isHidden {
				updateCamera()
			}
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		globeView.frame = bounds
	}

	/// Position the globe camera to match the flat map: same center, same scale at
	/// the center of the screen, same orientation.
	private func updateCamera() {
		guard !isHidden,
		      bounds.width > 0
		else { return }
		let transform = viewPort.mapTransform
		let center = viewPort.screenCenterLatLon()
		// The map transform's rotation turns the map clockwise on screen, so the compass
		// heading that ends up at the top of the screen is its negative.
		let heading = -transform.rotation() * 180.0 / .pi
		globeView.setCamera(latitude: center.lat,
		                    longitude: center.lon,
		                    heading: heading,
		                    mercatorZoom: transform.zoom())
	}
}

extension GlobeBasemapView: MapLayersView.LayerOrView {
	var hasTileServer: TileServer? {
		return tileServer
	}

	func removeFromSuper() {
		removeFromSuperview()
	}
}

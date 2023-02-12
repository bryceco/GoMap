//
//  QuestBuilder.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestBuilderFeatureCell: UICollectionViewCell {
	@IBOutlet var label: UILabel?
	@IBAction func deleteItem(_ sender: Any?) {
		onDelete?(self)
	}

	var onDelete: ((QuestBuilderFeatureCell) -> Void)?

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		contentView.layer.cornerRadius = 5
		contentView.layer.masksToBounds = true
	}
}

class QuestBuilder: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
	@IBOutlet var presetField: UIButton?
	@IBOutlet var includeFeaturesView: UICollectionView?
	@IBOutlet var excludeFeaturesView: UICollectionView?
	@IBOutlet var includeFeaturesHeightConstraint: NSLayoutConstraint?
	@IBOutlet var excludeFeaturesHeightConstraint: NSLayoutConstraint?

	var includeFeatures: [String] = []
	var excludeFeatures: [String] = []

	public class func instantiate() -> UIViewController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilder") as! QuestBuilder
		return vc
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		for featureView in [includeFeaturesView, excludeFeaturesView] {
			featureView?.layer.borderWidth = 1.0
			featureView?.layer.borderColor = UIColor.gray.cgColor
			featureView?.layer.cornerRadius = 5.0
		}

		if #available(iOS 13.0, *) {
			// prevent swiping down to dismiss
			self.isModalInPresentation = true
		}

		if let flowLayout = includeFeaturesView?.collectionViewLayout as? UICollectionViewFlowLayout {
			flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
		}

		if #available(iOS 14.0, *) {
			// get all possible fields
			let keys: [String] = PresetsDatabase.shared.presetFields.values
				.compactMap({ field in
					guard
						let key = field.key,
						!key.hasSuffix(":"), // multiCombo isn't supported
						!allFeaturesWithKey(key).isEmpty
					else {
						return nil
					}
					return key
				})
			let handler: (_: Any?) -> Void = { _ in self.didAddAllInclude(nil) }
			let presetItems: [UIAction] = Array(Set(keys))
				.sorted()
				.map { UIAction(title: "\($0)", handler: handler) }
			presetField?.menu = UIMenu(title: NSLocalizedString("Preset Field", comment: ""),
			                           children: presetItems)
			presetField?.showsMenuAsPrimaryAction = true
		}
	}

	@IBAction func didChangePresetKey(_ sender: Any?) {
		didAddAllInclude(nil)
	}

	@IBAction func didAddAllInclude(_ sender: Any?) {
		guard let key = presetField?.title(for: .normal) else { return }
		let features = allFeaturesWithKey(key)
		includeFeatures = features.map { $0.name }.sorted()
		includeFeaturesView?.reloadData()
	}

	@IBAction func didRemoveAllInclude(_ sender: Any?) {
		includeFeatures = []
		includeFeaturesView?.reloadData()
	}

	@IBAction func didAddAllExclude(_ sender: Any?) {
		guard let key = presetField?.title(for: .normal) else { return }
		let features = allFeaturesWithKey(key)
		excludeFeatures = features.map { $0.name }.sorted()
		excludeFeaturesView?.reloadData()
	}

	@IBAction func didRemoveAllExclude(_ sender: Any?) {
		excludeFeatures = []
		excludeFeaturesView?.reloadData()
	}

	func allFeaturesWithKey(_ key: String) -> [PresetFeature] {
		let presets = PresetsDatabase.shared.stdPresets.values.compactMap { feature in
			for fieldName in feature.fields ?? [] {
				guard let field = PresetsDatabase.shared.presetFields[fieldName] else { continue }
				if field.key == key {
					return feature
				}
			}
			return nil
		}
		return presets
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let heightInclude = includeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		includeFeaturesHeightConstraint?.constant = max(heightInclude, 25.0)

		let heightExclude = excludeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		excludeFeaturesHeightConstraint?.constant = max(heightExclude, 25.0)

		view.layoutIfNeeded()
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard section == 0 else { return 0 }
		if collectionView === includeFeaturesView {
			return includeFeatures.count
		}
		if collectionView == excludeFeaturesView {
			return excludeFeatures.count
		}
		return 0
	}

	func collectionView(_ collectionView: UICollectionView,
	                    cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
	{
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FeatureCell",
		                                              for: indexPath) as! QuestBuilderFeatureCell
		if collectionView === includeFeaturesView {
			cell.label?.text = includeFeatures[indexPath.row]
		} else {
			cell.label?.text = excludeFeatures[indexPath.row]
		}
		cell.onDelete = { cell in
			if let indexPath = collectionView.indexPath(for: cell) {
				if collectionView === self.includeFeaturesView {
					self.includeFeatures.remove(at: indexPath.row)
				} else {
					self.excludeFeatures.remove(at: indexPath.row)
				}
				collectionView.deleteItems(at: [indexPath])
				self.viewDidLayoutSubviews()
			}
		}
		return cell
	}
}

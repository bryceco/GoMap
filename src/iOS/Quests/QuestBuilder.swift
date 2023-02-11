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
	@IBOutlet var geometryArea: UIButton?
	@IBOutlet var geometryWay: UIButton?
	@IBOutlet var geometryNode: UIButton?
	@IBOutlet var geometryVertex: UIButton?
	@IBOutlet var includeFeaturesView: UICollectionView?
	@IBOutlet var excludeFeaturesView: UICollectionView?
	@IBOutlet var includeFeaturesHeightConstraint: NSLayoutConstraint?

	var includeFeatures: [String] = []
	var excludeFeatures: [String] = []

	public class func instantiate() -> UIViewController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilder") as! QuestBuilder
		return vc
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		includeFeaturesView?.layer.borderWidth = 1.0
		includeFeaturesView?.layer.borderColor = UIColor.gray.cgColor
		includeFeaturesView?.layer.cornerRadius = 5.0

		if let flowLayout = includeFeaturesView?.collectionViewLayout as? UICollectionViewFlowLayout {
			flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
		}

		if #available(iOS 15.0, *) {
			for button in [geometryArea!, geometryWay!, geometryNode!, geometryVertex!] {
				button.addAction(UIAction(handler: { _ in }), for: .touchUpInside)
			}

			// get all possible fields
			let keys: [String] = PresetsDatabase.shared.presetFields.values
				.compactMap({ field in
					guard
						let key = field.key,
						!key.hasSuffix(":") // multiCombo isn't supported
					else {
						return nil
					}
					return key
				})
			let presetItems: [UIAction] = Array(Set(keys))
				.sorted()
				.map { UIAction(title: "\($0)", handler: { _ in }) }
			presetField?.menu = UIMenu(title: NSLocalizedString("Preset Field", comment: ""),
			                           children: presetItems)
			presetField?.showsMenuAsPrimaryAction = true
		}
	}

	@IBAction func didToggleGeometry(_ sender: Any?) {
		guard let button = sender as? UIButton else { return }
		button.isSelected.toggle()
	}

	@IBAction func didAddAllInclude(_ sender: Any?) {
		guard let key = presetField?.title(for: .normal) else { return }
		let features = allFeaturesWithKey(key)
		includeFeatures = features.map{ $0.name }.sorted()
		includeFeaturesView?.reloadData()
	}

	func allFeaturesWithKey(_ key:String) -> [PresetFeature] {
		let presets = PresetsDatabase.shared.stdPresets.values.compactMap{ feature in
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

	@IBAction func didRemoveAllInclude(_ sender: Any?) {
		includeFeatures = []
		includeFeaturesView?.reloadData()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let height = includeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		includeFeaturesHeightConstraint?.constant = max(height, 25.0)
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

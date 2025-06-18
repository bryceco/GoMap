//
//  QuestBuilderController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class QuestBuilderFeatureCell: UICollectionViewCell {
	@IBOutlet var label: UILabel?
	@IBAction func deleteItem(_ sender: Any?) {
		onDelete?(self)
	}

	var onDelete: ((QuestBuilderFeatureCell) -> Void)?

	override func awakeFromNib() {
		super.awakeFromNib()
		contentView.layer.cornerRadius = 5
		contentView.layer.masksToBounds = true
	}
}

class QuestBuilderController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
	UITextFieldDelegate
{
	private typealias PresetsForKey = [String: ContiguousArray<PresetFeature>]

	@IBOutlet var presetField: UIButton?
	@IBOutlet var includeFeaturesView: UICollectionView?
	@IBOutlet var includeFeaturesHeightConstraint: NSLayoutConstraint?
	@IBOutlet var scrollView: UIScrollView?
	@IBOutlet var saveButton: UIBarButtonItem?
	@IBOutlet var nameField: UITextField? // Long name, like "Add Surface"
	@IBOutlet var labelField: UITextField? // Short name for a quest button, like "S"

	@IBOutlet var featuresSelectionButton: UISegmentedControl?
	@IBOutlet var includeOneFeatureButton: UIButton?
	@IBOutlet var removeAllIncludeButton: UIButton?
	@IBOutlet var addOneIncludeButton: UIButton?

	var quest: QuestDefinitionWithFeatures?

	private var primaryFeaturesForKey: PresetsForKey = [:]
	private var allFeaturesForKey: PresetsForKey = [:]

	private var availableFeatures: [PresetFeature] = [] // all features for current presetField
	private var chosenFeatures: [(name: String, ident: String)] = [] {
		didSet {
			removeAllIncludeButton?.isEnabled = chosenFeatures.count > 0
			addOneIncludeButton?.isEnabled = chosenFeatures.count < availableFeatures.count
			updateSaveButtonStatus()
		}
	}

	@available(iOS 15, *)
	public class func instantiateWith(quest: QuestDefinitionWithFeatures?) -> UIViewController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilder") as! QuestBuilderController
		vc.quest = quest
		return vc
	}

	@IBAction func onSave(_ sender: Any?) {
		do {
			let name = nameField!.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			let label = labelField!.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			let quest = QuestDefinitionWithFeatures(title: name,
			                                        label: label,
			                                        tagKey: presetField!.title(for: .normal)!,
			                                        includeFeatures: chosenFeatures.map { $0.ident })
			try QuestList.shared.addUserQuest(quest, replacing: self.quest)
			onCancel(sender)
		} catch {
			let alertView = UIAlertController(title: NSLocalizedString("Quest Definition Error", comment: ""),
			                                  message: error.localizedDescription,
			                                  preferredStyle: .alert)
			alertView.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
			                                  style: .cancel))
			present(alertView, animated: true)
			return
		}
	}

	@IBAction func onCancel(_ sender: Any?) {
		if navigationController?.popViewController(animated: true) == nil {
			dismiss(animated: true)
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		for featureView in [includeFeaturesView] {
			featureView?.layer.borderWidth = 1.0
			featureView?.layer.borderColor = UIColor.gray.cgColor
			featureView?.layer.cornerRadius = 5.0
			featureView?.isPrefetchingEnabled = false
		}

		// monitor changes to nameField
		nameField?.delegate = self
		nameField?.addTarget(self, action: #selector(nameFieldDidChange(_:)), for: .editingChanged)
		labelField?.delegate = self
		labelField?.addTarget(self, action: #selector(labelFieldDidChange(_:)), for: .editingChanged)
		saveButton?.isEnabled = false

		// monitor when keyboard is visible
		registerKeyboardNotifications()

		if #available(iOS 13.0, *) {
			// prevent swiping down to dismiss
			self.isModalInPresentation = true
		}

		if let flowLayout = includeFeaturesView?.collectionViewLayout as? UICollectionViewFlowLayout {
			flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
		}

		if #available(iOS 14.0, *) {
			// get all possible keys
			(primaryFeaturesForKey, allFeaturesForKey) = buildFeaturesForKeys()
			let handler: (_: Any?) -> Void = { [weak self] _ in self?.presetKeyChanged() }
			let presetItems: [UIAction] = allFeaturesForKey.keys.sorted()
				.map { UIAction(title: "\($0)", handler: handler) }
			presetField?.menu = UIMenu(title: NSLocalizedString("Tag Key", comment: ""),
			                           children: presetItems)
			presetField?.showsMenuAsPrimaryAction = true
		}

		let tagKey: String
		if let quest = quest {
			// if we're editing an existing quest then fill in the fields
			let features = PresetsDatabase.shared.stdFeatures
			chosenFeatures = quest.includeFeatures.map { (features[$0]?.name ?? $0, $0) }
			nameField?.text = quest.title
			labelField?.text = quest.label
			tagKey = quest.tagKey
		} else {
			tagKey = "cuisine"
		}

		// mark the current key selection
		if #available(iOS 14.0, *) {
			// select the current presetKey
			if let item = presetField?.menu?.children.first(where: { $0.title == tagKey }),
			   let action = item as? UIAction
			{
				action.state = .on
			}
		}
		presetKeyChanged()

		setupAddOneMenu(button: includeOneFeatureButton!,
		                featureList: { [weak self] in self?.chosenFeatures ?? [] },
		                featureView: includeFeaturesView!,
		                addFeature: { [weak self] in
		                	self?.chosenFeatures.append($0)
		                	self?.chosenFeatures.sort(by: { $0.name < $1.name })
		                })
	}

	private func setupAddOneMenu(button: UIButton,
	                             featureList: @escaping () -> [(name: String, ident: String)],
	                             featureView: UICollectionView,
	                             addFeature: @escaping ((name: String, ident: String)) -> Void)
	{
		if #available(iOS 15.0, *) {
			let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
				guard let self = self else { return }
				let featureList = featureList()
				let items: [UIAction] = self.availableFeatures.map {
					feature in UIAction(title: "\(feature.name)", handler: { _ in
						let newFeature = (feature.name, feature.featureID)
						if !featureList.contains(where: { $0.ident == newFeature.1 }) {
							addFeature(newFeature)
						}
						featureView.reloadData()
					})
				}
				completion(items)
			}
			button.menu = UIMenu(children: [
				UIAction(title: "", handler: { _ in }), // requires at least one non-deferred item
				deferred
			])
			button.showsMenuAsPrimaryAction = true
			button.setTitle("+", for: .normal)
		}
	}

	private func presetKeyChanged() {
		let key = presetField!.title(for: .normal)!
		let primaryCount = primaryFeaturesForKey[key]?.count ?? 0
		let allCount = allFeaturesForKey[key]?.count ?? 0
		if primaryCount < 5, allCount > primaryCount {
			useAllFeatures()
		} else {
			usePrimaryFeatures()
		}
	}

	@IBAction func PrimaryAllSelectorChanged(_ sender: Any?) {
		if let seg = sender as? UISegmentedControl {
			if seg.selectedSegmentIndex == 0 {
				usePrimaryFeatures()
			} else {
				useAllFeatures()
			}
		}
	}

	private func usePrimaryFeatures() {
		let key = presetField!.title(for: .normal)!
		availableFeatures = (primaryFeaturesForKey[key] ?? []).sorted(by: { a, b in a.name < b.name })
		chosenFeatures = availableFeatures.map { ($0.name, $0.featureID) }
		featuresSelectionButton?.selectedSegmentIndex = 0
		includeFeaturesView?.reloadData()
		includeFeaturesView?.layoutIfNeeded()
	}

	private func useAllFeatures() {
		let key = presetField!.title(for: .normal)!
		availableFeatures = (allFeaturesForKey[key] ?? []).sorted(by: { a, b in a.name < b.name })
		chosenFeatures = availableFeatures.map { ($0.name, $0.featureID) }
		featuresSelectionButton?.selectedSegmentIndex = 1
		includeFeaturesView?.reloadData()
		includeFeaturesView?.layoutIfNeeded()
	}

	@IBAction func removeAllIncludeFeatures(_ sender: Any?) {
		chosenFeatures = []
		includeFeaturesView?.reloadData()
	}

	private func buildFeaturesForKeys() -> (PresetsForKey, PresetsForKey) {
		func addFields(to dict: inout PresetsForKey, forFeature feature: PresetFeature, fieldNameList: [String]) {
			for fieldName in fieldNameList {
				guard let field = PresetsDatabase.shared.presetFields[fieldName] else { continue }
				for key in field.allKeys {
					/*
					 if field.reference?["key"] == key {
					 	continue
					 }
					  */
					if dict[key]?.append(feature) == nil {
						dict[key] = [feature]
					}
				}
			}
		}

		var primaryFeatures = PresetsForKey()
		for feature in PresetsDatabase.shared.stdFeatures.values {
			addFields(to: &primaryFeatures, forFeature: feature, fieldNameList: feature.fields ?? [])
		}
		var allFeatures = primaryFeatures
		for feature in PresetsDatabase.shared.stdFeatures.values {
			addFields(to: &allFeatures, forFeature: feature, fieldNameList: feature.moreFields ?? [])
		}

		return (primaryFeatures, allFeatures)
	}

	static func presentVersionAlert(_ vc: UIViewController) {
		let alert = UIAlertController(
			title: NSLocalizedString("Error", comment: ""),
			message: NSLocalizedString("This feature is only available on iOS 15 or later", comment: ""),
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
		vc.present(alert, animated: true)
	}

	// MARK: Collection View

	override func viewWillLayoutSubviews() {
		let heightInclude = includeFeaturesView?.collectionViewLayout.collectionViewContentSize.height ?? 0.0
		includeFeaturesHeightConstraint?.constant = max(heightInclude, 25.0)
		super.viewWillLayoutSubviews()
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard section == 0 else { return 0 }
		if collectionView === includeFeaturesView {
			return chosenFeatures.count
		}
		return 0
	}

	func collectionView(_ collectionView: UICollectionView,
	                    cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
	{
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FeatureCell",
		                                              for: indexPath) as! QuestBuilderFeatureCell
		cell.label?.text = chosenFeatures[indexPath.row].name
		cell.onDelete = { [weak self] cell in
			if let self = self,
			   let indexPath = collectionView.indexPath(for: cell)
			{
				self.chosenFeatures.remove(at: indexPath.row)
				collectionView.deleteItems(at: [indexPath])
				self.view.setNeedsLayout()
			}
		}
		return cell
	}

	// MARK: Name and label

	private func updateSaveButtonStatus() {
		let name = nameField?.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		let label = labelField?.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		saveButton?.isEnabled = name != "" &&
			(QuestInstance.isCharacter(label: label) || QuestInstance.isImage(label: label))
	}

	@objc func nameFieldDidChange(_ sender: Any?) {
		updateSaveButtonStatus()
	}

	@objc func labelFieldDidChange(_ sender: Any?) {
		updateSaveButtonStatus()
	}

	// MARK: keyboard

	@objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return false
	}

	private func registerKeyboardNotifications() {
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(keyboardWillShow(notification:)),
		                                       name: UIResponder.keyboardWillShowNotification,
		                                       object: nil)
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(keyboardWillHide(notification:)),
		                                       name: UIResponder.keyboardWillHideNotification,
		                                       object: nil)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		NotificationCenter.default.removeObserver(self)
	}

	@objc func keyboardWillShow(notification: NSNotification) {
		if let userInfo: NSDictionary = notification.userInfo as? NSDictionary,
		   let keyboardInfo = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue
		{
			guard let scrollView = scrollView,
			      let nameField = nameField
			else { return }
			let keyboardSize = keyboardInfo.cgRectValue.size
			let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
			scrollView.contentInset = contentInsets
			scrollView.scrollIndicatorInsets = contentInsets
			let rect = nameField.frame.offsetBy(dx: 0, dy: keyboardSize.height)
			scrollView.scrollRectToVisible(rect, animated: true)
		}
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		scrollView?.contentInset = .zero
		scrollView?.scrollIndicatorInsets = .zero
	}
}

//
//  QuestBuilder.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestBuilder: UIViewController {
	@IBOutlet var presetField: UIButton?
	@IBOutlet var geometryArea: UIButton?
	@IBOutlet var geometryWay: UIButton?
	@IBOutlet var geometryNode: UIButton?
	@IBOutlet var geometryVertex: UIButton?

	override func viewDidLoad() {
		super.viewDidLoad()

		if #available(iOS 15.0, *) {
			for button in [geometryArea!, geometryWay!, geometryNode!, geometryVertex!] {
				button.addAction(UIAction(handler: { _ in }), for: .touchUpInside)
			}

			// get all possible fields
			let presetItems: [UIAction] = Array(PresetsDatabase.shared.presetFields)
				.compactMap({ ident, field in
					guard
						let key = field.key,
						!key.hasSuffix(":") // multiCombo isn't supported
					else {
						return nil
					}
					return UIAction(title: "\(key) - \(field.label ?? ident)", handler: { _ in })
				})
				.sorted(by: { a, b in a.title < b.title })
#if DEBUG
			print("\n")
			for p in presetItems {
				print("\(p.title)")
			}
#endif
			presetField?.menu = UIMenu(title: NSLocalizedString("Preset Field", comment: ""),
			                           children: presetItems)
			presetField?.showsMenuAsPrimaryAction = true
		}
	}

	public class func instantiate() -> UIViewController {
		let sb = UIStoryboard(name: "QuestBuilder", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "QuestBuilder") as! QuestBuilder
		return vc
	}
}

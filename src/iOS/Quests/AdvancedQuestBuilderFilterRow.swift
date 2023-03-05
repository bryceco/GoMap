//
//  AdvancedQuestBuilderFilterRow.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/19/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import SwiftUI

@available(iOS 15.0.0, *)
struct AdvancedQuestFilterRowView: View {
	@Binding var data: QuestDefinitionFilter

	var body: some View {
		HStack {
			// Key textfield
			TextField("", text: $data.tagKey)
				.textFieldStyle(.roundedBorder)
				.autocapitalization(.none)
				.autocorrectionDisabled()
				.keyboardType(.asciiCapable)

			// relation button
			Menu {
				Button(QuestDefinitionFilter.Relation.equal.rawValue, action: { data.relation = .equal })
				Button(QuestDefinitionFilter.Relation.notEqual.rawValue, action: { data.relation = .notEqual })
			} label: {
				Label(data.relation.rawValue, systemImage: "book.fill").labelStyle(TitleOnlyLabelStyle())
			}

			// value textfield
			TextField("", text: $data.tagValue)
				.textFieldStyle(RoundedBorderTextFieldStyle())
				.autocapitalization(.none)
				.autocorrectionDisabled()
				.keyboardType(.asciiCapable)
			
			// include/exclude button
			Menu {
				Button(QuestDefinitionFilter.Included.include.rawValue, action: { data.included = .include })
				Button(QuestDefinitionFilter.Included.exclude.rawValue, action: { data.included = .exclude })
			} label: {
				Label(data.included.rawValue, systemImage: "book.fill").labelStyle(TitleOnlyLabelStyle())
			}
		}
	}
}

@available(iOS 15.0, *)
struct AdvancedQuestBuilderFilterRow_Previews: PreviewProvider {
	@State static var data = QuestDefinitionFilter(tagKey: "", tagValue: "", relation: .equal, included: .include)
	static var previews: some View {
		AdvancedQuestFilterRowView(data: $data)
	}
}

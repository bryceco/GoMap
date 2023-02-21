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
	@Binding var data: QuestTagFilter

	var body: some View {
		HStack {
			TextField("", text: $data.tagKey)
				.textFieldStyle(.roundedBorder)
				.autocapitalization(.none)

			Menu {
				Button(QuestTagFilter.Relation.equal.rawValue, action: { data.relation = .equal })
				Button(QuestTagFilter.Relation.notEqual.rawValue, action: { data.relation = .notEqual })
			} label: {
				Label(data.relation.rawValue, systemImage: "book.fill").labelStyle(TitleOnlyLabelStyle())
			}

			TextField("", text: $data.tagValue)
				.textFieldStyle(RoundedBorderTextFieldStyle())
				.autocapitalization(.none)

			Menu {
				Button(QuestTagFilter.Included.include.rawValue, action: { data.included = .include })
				Button(QuestTagFilter.Included.exclude.rawValue, action: { data.included = .exclude })
			} label: {
				Label(data.included.rawValue, systemImage: "book.fill").labelStyle(TitleOnlyLabelStyle())
			}
		}
	}
}

@available(iOS 15.0, *)
struct AdvancedQuestBuilderFilterRow_Previews: PreviewProvider {
	@State static var data = QuestTagFilter(tagKey: "", tagValue: "", relation: .equal, included: .include)
	static var previews: some View {
		AdvancedQuestFilterRowView(data: $data)
	}
}

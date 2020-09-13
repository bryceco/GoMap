//
//  EditFilterViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 09.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

class EditFilterViewController: UITableViewController {
    private let textFieldCellReuseIdentifier = "TextFieldCell"
    private let textLabelCellReuseIdentifier = "TextLabelCell"
    private let pickerViewCellReuseIdentifier = "PickerViewCell"

    private let viewModel = EditFilterViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.delegate = self
    }

    // MARK: - Private methods

    @IBAction private func didTapAddConditionButton() {
        viewModel.addCondition()
    }

    // MARK: - Table view data source

    override func numberOfSections(in _: UITableView) -> Int {
        return viewModel.sections.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]

        let cell: UITableViewCell
        switch row {
        case let .textField(placeholder, value):
            let textFieldCell = tableView.dequeueReusableCell(withIdentifier: textFieldCellReuseIdentifier, for: indexPath) as! TextFieldTableViewCell
            textFieldCell.update(placeholder: placeholder, text: value)

            cell = textFieldCell
        case let .operationPickerToggle(operation):
            let textLabelCell = tableView.dequeueReusableCell(withIdentifier: textLabelCellReuseIdentifier, for: indexPath)
            textLabelCell.textLabel?.text = operation.humanReadableString

            cell = textLabelCell
        case let .operationPicker(operation):
            let pickerViewCell = tableView.dequeueReusableCell(withIdentifier: pickerViewCellReuseIdentifier, for: indexPath) as! PickerViewTableViewCell
            pickerViewCell.selectOperation(operation)
            pickerViewCell.delegate = self

            cell = pickerViewCell
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.selectRow(at: indexPath)

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension EditFilterViewController: PickerViewTableViewCellDelegate {
    func pickerViewCell(_ pickerViewCell: PickerViewTableViewCell, didSelectOperation operation: EditFilterViewModel.Operation) {
        guard let section = tableView.indexPath(for: pickerViewCell)?.section else { return }

        viewModel.changeOperationForSection(section, toOperation: operation)
    }
}

extension EditFilterViewController: EditFilterViewModelDelegate {
    func insertSection(_ section: Int) {
        tableView.insertSections(IndexSet(integer: section), with: .fade)
    }

    func addRows(at indexPaths: [IndexPath]) {
        tableView.insertRows(at: indexPaths, with: .fade)
    }

    func removeRows(at indexPaths: [IndexPath]) {
        tableView.deleteRows(at: indexPaths, with: .fade)
    }

    func showKeyboardForTextFieldCell(at indexPath: IndexPath) {
        guard let textFieldCell = tableView.cellForRow(at: indexPath) as? TextFieldTableViewCell else { return }

        _ = textFieldCell.becomeFirstResponder()

//        /// TODO: Move to dedicated delegate method?
//        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
    }

    func setTextForTextLabelCell(at indexPath: IndexPath, to text: String) {
        guard let textFieldCell = tableView.cellForRow(at: indexPath) else { return }

        textFieldCell.textLabel?.text = text
    }
}

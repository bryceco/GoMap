//
//  AutocompleteTextField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

// this needs to be shared, because sometimes we'll create a new autocomplete text field when the keyboard is already showing,
// so it never gets a chance to retrieve the size:
private var s_keyboardFrame = CGRect.zero

let GradientHeight: CGFloat = 20.0

@objcMembers
class AutocompleteTextField: UITextField, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {
    
    func updateAutocomplete(for text: String?) {
        var text = text
        if text == " " {
            text = ""
        }
        // filter completion list by current text
        if (text?.count ?? 0) != 0 {
            filteredCompletions =
                (allStrings as NSArray).filtered(using: NSPredicate(block: { object, bindings in
                return ((object as? NSString) ?? "").range(of: text ?? "", options: .caseInsensitive).location == 0
            }))
        } else {
            filteredCompletions = allStrings as [Any]
        }
        // sort alphabetically
        filteredCompletions = (filteredCompletions as NSArray?)?.sortedArray(comparator: { s1, s2 in
            return ((s1 as? NSString) ?? "").compare((((s2 as? NSString) ?? "") as String), options: .caseInsensitive)
        })
        updateCompletionTableView()
    }
    
    weak var realDelegate: UITextFieldDelegate?
    var completionTableView: UITableView?
    var origCellOffset: CGFloat = 0.0
    var filteredCompletions: [Any]?
    var gradientLayer: CAGradientLayer?
    var didSelectAutocomplete: (() -> Void)?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)

        super.delegate = self
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        delegate = nil
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        assert(false) // not supported
    }
    
    override weak var delegate: UITextFieldDelegate? {
        get {
            realDelegate
        } set(_delegate) {
            realDelegate = _delegate
        }
    }

    func clearFilteredCompletionsInternal() {
        filteredCompletions = nil
        updateCompletionTableView()
    }
    
    private var allStrings: [String] = []
    
    var autocompleteStrings: [String]? {
        get {
            return allStrings
        }
        set(strings) {
            allStrings = strings ?? []
        }
    }
    
    func keyboardFrame(from notification: Notification?) -> CGRect {
        let userInfo = notification?.userInfo
        let rect = (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as AnyObject).cgRectValue ?? .zero
        return rect
    }

    @objc func keyboardWillShow(_ nsNotification: Notification?) {
        s_keyboardFrame = keyboardFrame(from: nsNotification)

        if isEditing && filteredCompletions?.count != nil {
            updateAutocomplete()
        }
    }

    // keyboard size can change if switching languages inside keyboard, etc.
    @objc func keyboardWillChange(_ nsNotification: Notification?) {
        s_keyboardFrame = keyboardFrame(from: nsNotification)

        if completionTableView != nil {
            let rect = frameForCompletionTableView()
            completionTableView?.frame = rect

            var rcGradient = rect
            rcGradient.size.height = GradientHeight

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.0)
            gradientLayer?.frame = rcGradient
            CATransaction.commit()
        }
        if isEditing && filteredCompletions?.count != nil {
            updateAutocomplete()
        }
    }

    func frameForCompletionTableView() -> CGRect {
        var cell: UIView? = superview
        while cell != nil && !(cell is UITableViewCell) {
            cell = cell?.superview
        }
        var tableView: UIView? = cell?.superview
        while tableView != nil && !(tableView is UITableView) {
            tableView = tableView?.superview
        }

        let cellRC = cell?.convert(cell?.bounds ?? CGRect.zero, to: tableView)
        var rect = CGRect.zero
        rect.origin.x = 0
        rect.origin.y = (cellRC?.origin.y ?? 0.0) + (cellRC?.size.height ?? 0.0)
        rect.size.width = tableView?.frame.size.width ?? 0.0
        if s_keyboardFrame.size.height > 0 {
            let keyboardPos = tableView?.convert(s_keyboardFrame, from: nil) // keyboard is in screen coordinates
            rect.size.height = (keyboardPos?.origin.y ?? 0.0) - rect.origin.y
        } else {
            // no on-screen keyboard (external keyboard or Mac Catalyst)
            rect.size.height = (tableView?.frame.size.height ?? 0.0) - (cellRC?.size.height ?? 0.0)
        }
        return rect
    }

    func updateCompletionTableView() {
        if filteredCompletions?.count != nil {
            if completionTableView == nil {

                var cell: UIView? = superview
                while cell != nil && !(cell is UITableViewCell) {
                    cell = cell?.superview
                }
                
                var tableView: UIView? = cell?.superview
                while tableView != nil && !(tableView is UITableView) {
                    tableView = tableView?.superview
                }

                guard let _tableView = tableView as? UITableView else { return }
                // scroll cell to top
                var p: IndexPath? = nil
                if let cell = cell as? UITableViewCell {
                    p = _tableView.indexPath(for: cell)
                }
                if let p = p {
                    _tableView.scrollToRow(at: p, at: .top, animated: false)
                }
                _tableView.isScrollEnabled = false

                // cell doesn't always scroll to the same place, so give it a moment before we add the completion table
                DispatchQueue.main.async(execute: {
                    // add completion table to tableview
                    let rect = self.frameForCompletionTableView()
                    self.completionTableView = UITableView(frame: rect, style: .plain)

                    var backgroundColor = UIColor(white: 0.88, alpha: 1.0)
                    if #available(iOS 13.0, *) {
                        backgroundColor = UIColor.systemBackground
                    }
                    self.completionTableView?.backgroundColor = backgroundColor
                    self.completionTableView?.separatorColor = UIColor(white: 0.7, alpha: 1.0)
                    self.completionTableView?.dataSource = self
                    self.completionTableView?.delegate = self
                    if let view = self.completionTableView {
                        tableView?.addSubview(view)
                    }

                    self.gradientLayer = CAGradientLayer()
                    self.gradientLayer?.colors = [
                        UIColor(white: 0.0, alpha: 0.6).cgColor,
                        UIColor(white: 0.0, alpha: 0.0).cgColor
                    ].compactMap { $0 }
                    var rcGradient = rect
                    rcGradient.size.height = GradientHeight
                    self.gradientLayer?.frame = rcGradient
                    if let layer = self.gradientLayer {
                        tableView?.layer.addSublayer(layer)
                    }
                })
            }
            completionTableView?.reloadData()
        } else {
            completionTableView?.removeFromSuperview()
            completionTableView = nil

            gradientLayer?.removeFromSuperlayer()
            gradientLayer = nil

            var cell: UIView? = superview
            while cell != nil && !(cell is UITableViewCell) {
                cell = cell?.superview as? UITableViewCell
            }
            var tableView: UIView? = cell?.superview
            while tableView != nil && !(tableView is UITableView) {
                tableView = tableView?.superview as? UITableView
            }
            if let tableView = tableView {
                var cellIndexPath: IndexPath? = nil
                if let cell = cell as? UITableViewCell {
                    cellIndexPath = (tableView as? UITableView)?.indexPath(for: cell)
                }
                if let cellIndexPath = cellIndexPath {
                    (tableView as? UITableView)?.scrollToRow(at: cellIndexPath, at: .middle, animated: true)
                }
            }
            (tableView as? UITableView)?.isScrollEnabled = true
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        text = filteredCompletions?[indexPath.row] as? String

        sendActions(for: .editingChanged)
        // [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:self userInfo:nil];

        if let didSelectAutocomplete = didSelectAutocomplete {
            didSelectAutocomplete()
        }

        // hide completion table view
        filteredCompletions = nil
        updateCompletionTableView()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredCompletions?.count ?? 0
    }

    static let tableViewCellIdentifier = "Cell"

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: AutocompleteTextField.tableViewCellIdentifier)
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: AutocompleteTextField.tableViewCellIdentifier)
            cell?.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        }
        cell?.textLabel?.text = filteredCompletions?[indexPath.row] as? String
        return cell!
    }

    func updateAutocomplete() {
        updateAutocomplete(for: text)
    }

// MARK: delegate

    // Forward any delegate messages to the real delegate
    @objc func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldBeginEditing(_:))) ?? false {
            return realDelegate?.textFieldShouldBeginEditing?(textField) ?? false
        }
        return true
    }

    @objc func textFieldDidBeginEditing(_ textField: UITextField) {
        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidBeginEditing(_:))) ?? false {
            realDelegate?.textFieldDidBeginEditing?(textField)
        }
    }

    @objc func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldEndEditing(_:))) ?? false {
            return realDelegate?.textFieldShouldEndEditing?(textField) ?? false
        }
        return true
    }

    @objc func textFieldDidEndEditing(_ textField: UITextField) {
        clearFilteredCompletionsInternal()

        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidEndEditing(_:))) ?? false {
            realDelegate?.textFieldDidEndEditing?(textField)
        }
    }

    @objc func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        clearFilteredCompletionsInternal()

        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidEndEditing(_:reason:))) ?? false {
            realDelegate?.textFieldDidEndEditing?(textField, reason: reason)
        } else if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidEndEditing(_:))) ?? false {
            realDelegate?.textFieldDidEndEditing?(textField)
        }
    }

    @objc func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let result = Bool((realDelegate?.responds(to: #selector(UITextFieldDelegate.textField(_:shouldChangeCharactersIn:replacementString:))) ?? false
            ? realDelegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string)
            : true) ?? false)
        if result {
            let newString = (text as NSString?)?.replacingCharacters(in: range, with: string)
            updateAutocomplete(for: newString)
        }
        return result
    }

    @objc func textFieldDidChangeSelection(_ textField: UITextField) {
        if #available(iOS 13.0, *) {
            if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidChangeSelection(_:))) ?? false {
                realDelegate?.textFieldDidChangeSelection?(textField)
            }
        }
    }

    @objc func textFieldShouldClear(_ textField: UITextField) -> Bool {
        let result = Bool((realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldClear(_:))) ?? false
            ? realDelegate?.textFieldShouldClear?(textField)
            : true) ?? false)
        if result {
            updateAutocomplete(for: "")
        }
        return result
    }

    @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldReturn(_:))) ?? false {
            return realDelegate?.textFieldShouldReturn?(textField) ?? false
        }
        return true
    }
}

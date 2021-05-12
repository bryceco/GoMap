//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  NotesTableViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/4/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import MapKit
import UIKit

@objcMembers
class NotesTableViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    var newComment: String?

    @IBOutlet var tableView: UITableView!
    var note: OsmNote?
    var mapView: MapView?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableView.automaticDimension

        // add extra space at bottom so keyboard doesn't cover elements
        var rc = tableView.contentInset
        rc.bottom += 70
        tableView.contentInset = rc
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    // MARK: - Table view data source

    func numberOfSections(in tableView: UITableView) -> Int {
        return (note?.comments != nil) ? 2 : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (note?.comments != nil) && section == 0 {
            return NSLocalizedString("Note History", comment: "OSM note")
        } else {
            return NSLocalizedString("Update", comment: "update an osm note")
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            return "\n\n\n\n\n\n\n\n\n"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ((note?.comments != nil) && section == 0 ? note?.comments.count : 2) ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (note?.comments != nil) && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "noteCommentCell", for: indexPath) as? NotesCommentCell
            let comment = note?.comments[indexPath.row] as? OsmNoteComment
            cell?.date.text = comment?.date
            if let action = comment?.action {
                cell?.user.text = "\(comment?.user ?? "anonymous") - \(action)"
            }
            if comment?.text.count == 0 {
                cell?.commentBackground.isHidden = true
                cell?.comment.text = nil
            } else {
                cell?.commentBackground.isHidden = false
                cell?.commentBackground.layer.cornerRadius = 5
                cell?.commentBackground.layer.borderColor = UIColor.black.cgColor
                cell?.commentBackground.layer.borderWidth = 1.0
                cell?.commentBackground.layer.masksToBounds = true
                cell?.comment.text = comment?.text
            }
            return cell!
        } else if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "noteResolveCell", for: indexPath) as? NotesResolveCell
            cell?._text.layer.cornerRadius = 5.0
            cell?._text.layer.borderColor = UIColor.black.cgColor
            cell?._text.layer.borderWidth = 1.0
            cell?._text.delegate = self
            cell?._text.text = newComment
            cell?.commentButton.isEnabled = false
            cell?.resolveButton.isEnabled = note?.comments != nil
            return cell!
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "noteDirectionsCell", for: indexPath) as UITableViewCell
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        view.endEditing(true)

        if (self.note?.comments != nil) && indexPath.section == 0 {
            // ignore
        } else if indexPath.row == 1 {
            // get directions
            let coordinate = CLLocationCoordinate2DMake(self.note?.lat ?? 0, self.note?.lon ?? 0)
            let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: nil)
            let note = MKMapItem(placemark: placemark)
            note.name = "OSM Note"
            let current = MKMapItem.forCurrentLocation()
            let options = [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
            MKMapItem.openMaps(with: [current, note], launchOptions: options)
        }
    }

    func commentAndResolve(_ resolve: Bool, sender: Any?) {
        view.endEditing(true)
        var cell = (sender as AnyObject).superview as? NotesResolveCell
        while cell != nil && !(cell is NotesResolveCell) {
            cell = cell?.superview as? NotesResolveCell
        }
        if let cell = cell {
            let s = cell._text.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let alert = UIAlertController(title: NSLocalizedString("Updating Note...", comment: "OSM Note"), message: nil, preferredStyle: .alert)
            present(alert, animated: true)

            mapView?.notesDatabase.update(note, close: resolve, comment: s) { [self] newNote, errorMessage in
                alert.dismiss(animated: true)
                if let newNote = newNote {
                    note = newNote
                    DispatchQueue.main.async(execute: { [self] in
                        done(nil)
                        mapView?.refreshNoteButtonsFromDatabase()
                    })
                } else {
                    let alert2 = UIAlertController(title: NSLocalizedString("Error", comment: ""), message: errorMessage, preferredStyle: .alert)
                    alert2.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                    present(alert2, animated: true)
                }
            }
        }
    }

    @IBAction func doComment(_ sender: Any) {
        commentAndResolve(false, sender: sender)
    }

    @IBAction func doResolve(_ sender: Any) {
        commentAndResolve(true, sender: sender)
    }

    func textViewDidChange(_ textView: UITextView) {
        var cell = textView.superview as? NotesResolveCell
        while cell != nil && !(cell is NotesResolveCell) {
            cell = cell?.superview as? NotesResolveCell
        }
        if let cell = cell {
            newComment = cell._text.text
            let s = newComment?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            cell.commentButton.isEnabled = (s?.count ?? 0) > 0
        }
    }

    @IBAction func done(_ sender: Any?) {
        dismiss(animated: true)
    }
}

class NotesCommentCell: UITableViewCell {
    @IBOutlet var date: UILabel!
    @IBOutlet var user: UILabel!
    @IBOutlet var comment: UITextView!
    @IBOutlet var commentBackground: UIView!
}

class NotesResolveCell: UITableViewCell {
    @IBOutlet var _text: UITextView!
    @IBOutlet var commentButton: UIButton!
    @IBOutlet var resolveButton: UIButton!
}

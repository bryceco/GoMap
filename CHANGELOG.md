# Changelog

## 3.4.8

- Add highlighting of set tags in All Tags
- Correctly handle renaming key in key/value table cells in Common Tags
- Update translations

## 3.4.7 

- Fixes crash when editing description=* (and related keys) fields in Common Tags
- Key/Value pairs in Common Tags now behave more similar to All Tags
- Various minor bug fixes

## 3.4.6

- Fixes a hang when user-defined presets contained non-ASCII characters.
- Fixes a bug with pressing quest buttons
- Updates translations

## 3.4.5

- Fix issues displaying Mapbox aerial imagery
- Enable tap-and-drag to zoom, 

## 3.4.4

- Ruler is now localized and has new behavior
- Opening hours recognition supports "noon" & "midnight"
- Updates translations
- Lots of bug fixes

## 3.4.3

- Various bug fixes

## 3.4.2

- Various bug fixes

## 3.4.1

- Minor bug fixes

## 3.4.0

- Fixes bugs in opening_hours camera use
- opening_hours will now format inputs for you, so "mo-fr 8-15" will become "Mo-Fr 08:00-15:00"
- Fixes various crashes on iOS 12

## 3.3.9

- More bug fixes
- Stores Custom Presets on openstreetmap.com so they can be shared between devices.
- Updates translations
- Displays feature icons in Common Tags

## 3.3.8

- Adds a "Needs Survey" quest. 
- Adds geometry filter to advanced quests builder
- Selecting an object highlights the related quest
- Quests with presets now also include a text entry field
- Various bug fixes

## 3.3.7 

- Fixes a bunch of UI issues when tagging things.
- Adds the ability to share Google Maps locations to Go Map!! (it already supported Apple Maps, Organic Maps and plain old OSM URLs).

As before:
* Advanced quest builder now supports multiple answer keys
* Adds more built-in quests
* Unifies support for accessory buttons across Common Tags, All Tags, and Quests.
* Fixes a crash during launch in older iOS versions
* Fixes an issue with reading the aerial imagery database

## 3.3.6

- Advanced quest builder now supports multiple answer keys
- Adds more built-in quests
- Unifies support for accessory buttons across Common Tags, All Tags, and Quests.
- Fixes a crash during launch in older iOS versions
- Fixes an issue with reading the aerial imagery database

## 3.3.5

- Advanced quest builder now supports multiple answer keys
- Adds more built-in quests
- Uniform support for accessory buttons across Common Tags, All Tags, and Quests.
- Fixes a crash during launch in older iOS versions
- Fixes an issue with reading the aerial imagery database

## 3.3.3 

- Adds a new Advanced Quest Builder to provide finer grained control over filters.

## 3.3.0

- Implements StreetComplete style quests (enable them on the Display page). Initially there are just a few, but you can also easily define your own, and I'm happy to add quests to the built-in set. 
- Fixes Maxar imagery
- Fixes minor issues with Opening Hours recognizer
- Fixes some issues with drawing water areas

## 3.2.1

- Authentication now uses OAuth 2.0. You'll be prompted to authenticate the first time you try to upload. This change breaks the ability to use an alternate server (e.g. https://www.openhistoricalmap.org). If this affects you and you'd like a fix for it please contact me and I'll add support back in.
- Increases system requirements to iOS 12.  
- Fixes a problem with displaying recently used changeset messages.
- Fixes an issue with area=yes not being automatically added for some presets
- Lots of refactoring and code cleanup, as well as moving to more modern APIs. 
- Updates translations and other minor bug fixes and improvements.

## 3.1.11

- Only show magnifying glass after dragging an object
- Adds support for multi-line tag values in Common Tags and All Tags (note=*, description=*, etc)
- Adds swipe-to-delete in Common Tags
- Common Tags highlight color is now blue instead of green

## 3.1.10

- Imported GPX files containing waypoints now drops a marker that is visible when Notes & Fixmes is enabled.
- Common Tags now displays any tags missing a preset in a format similar to All Tags.
- Common Tags now highlights tags that are defined.
- Changeset comments now support history.
- Magnifying glass now appears when editing nodes.

## 3.1.9

- Improves heuristics for when we suggest better aerial imagery
- Updates translations

## 3.1.8

- Updates presets to use 5.0 preset schema. 
- Lots of improvements relating to only showing NSI brands in appropriate locations. There may be some bugs so if you see a preset that seems to be for a different country be sure to file a bug on it. 
- You can now share an Organic Maps (open source replacement for Maps.me) URL to Go Map!! and it will properly interpret the lat/lon encoding. If there's demand for Maps.me support as well it's probably trivial to add.
- Updates translations 
- A couple minor Mac Catalyst fixes

## 3.1.6

- App will now prompt to use "best" imagery when available
- Displays the area of closed ways in Attributes tab
- Search button now handles coordinates like 26°35'36"N 106°40'44"E
- Miscellaneous UI improvements
- Updates translations and name suggestion index

## 3.1.5

- iOS 16 updates
- Adds a kph/mph toggle to maxspeed preset
- Updates presets
- Updates translations
- Minor bug fixes

## 3.1.4

- Updates presets 
- Fixes some presets bugs 
- Fix a bug with deep linking URLs 
- Removes Maxar Standard imagery (Premium remains) 
- Fix a bug with GPX display when zooming out

Adds Brazilian Portuguese  * Fixes some hit-testing issues with the pushpin

## 3.1.0

- 'All Tags' tab now has a Feature picker
- Supports double-tap and drag for zooming
- Aerial imagery providers now highlight "best" layers
- Fixes issues with autocomplete
- Crash fixes
- Updated translations
- Mac Catalyst improvements

## 3.0.0

- Now written in Swift!
- Support for many new languages
- Improves support when sharing GPX files or URLs to the app
- Improved search: search by lat/lon, OSM node/way ID, etc.
- Many bug fixes and minor improvements

## 2.2.1

- Various bug fixes
- Adds support for Mac Catalyst
- Improved internationalization and languages
- Adds camera-based reading of `opening_hours` on signs

## 2.1.2

- Updated translations, presets, and name suggestion index
- New Yes/No switches for boolean presets
- Multi-Combo presets (such as "Diet Types") are now presented in prettier and more compact manner
- Various bug fixes
- Drops support for iOS 9

## 2.0.7

- New look, new presets!
- Now fully localized for Russian, Japanese, French and Croatian
- Mostly localized for Chinese (Traditional and Simplified), Norwegian, Finnish and German

## 1.8.42

Fixes a bug preventing OSM data from being downloaded.

## 1.8.41

Fixes a bug causing the map location to reset on older devices

## 1.8.4

- Fix a bug where tag values were sometimes set incorrectly
- Allow zooming out a greater amount when editing sparse, rural areas.

## 1.8.2

- Bug fixes
- Support brand name suggestions
- Redesign of 'All Tags' view
- Performance improvements
- Many small Ul improvements

## 1.7.1

- Fixes an issue where presets for a feature were not correctly populated.
- Adds Beta testing & GitHub information to 'Contact Us'

## 1.7.0

- Updated presets
- Dark mode and other UI improvements
- Various bug fixes and improvements

## 1.6.1

Fixes a crash when editing a multipolygon that is only partially downloaded.

## 1.6

- Bug fixes and usability improvements
- Support for creating and editing multipolygon relations
- Much improved detection of edits that damage relations
- Now trims the object cache automatically as needed
- Supports dynamic type, allowing font size to be adjusted
- Upload screen now contains links back to modified objects

## 1.5.3

- Fixes crash during launch

## 1.5.2

Bug fixes:

-`payment:*` and `service:*` tags incorrectly formatted
- crash when a relation contains itself as a member

## 1.5.1

- Updated for iOS 11 and iPhone X
- Updated presets
- Multilingual presets (select language in 'Settings' pane)
- Turn restriction editor
- Duplicate and rotate objects
- Record GPX tracks in the background
- Support for many more background image sources
- Shows compass heading
- App badge display number of pending edits
- Connect to alternate OSM servers

## 1.5

- Updated for iOS 11 and iPhone X
- Updated presets
- Multilingual presets (select language in 'Settings' pane)
- Turn restriction editor
- Duplicate and rotate objects
- Record GPX tracks in the background
- Support for many more background image sources
- Shows compass heading
- App badge display number of pending edits
- Connect to alternate OSM servers

## 1.4

- Updated for iOS 9
- Faster and more stable
- iD based preset categories
- Create, upload and download GPX traces
- Create and resolve Notes
- Rotated and birds-eye (3-D) views

## 1.3.1

Fixes an issue with Undo introduced by version 1.3

## 1.3

Version 1.3 features improved graphics performance, map rotation, and new editing options.

## 1.2.1

- Updated for iOS 8
- New editing commands: Copy/Paste tags, Join, Split, Straighten, etc.
- Customizable backgrounds, including MapBox and OSM GPS traces
- Improved presets for common types of objects
- Define your own presets
- Performance improvements

## 1.1

- Improved tagging for highways and ways
- Autocomplete for tag keys and values
- Fixes font issues affecting Asian and Russian street names
- More icons for points of interest
- Various bug fixes and other improvements

## 1.0

- Initial release

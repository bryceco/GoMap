
# Go Map!!

Go Map!! is an iPhone/iPad editor for adding cartographic information to [OpenStreetMap][1].

[![Download on the App Store badge][2]][3]

## Join our TestFlight beta!

Do you want to help testing pre-releases of Go Map!!?
[Become a TestFlight tester][4] today! 🚀

## Continuous integration

### Prerequisite

- Make sure you have _fastlane_ installed. (From a terminal, change to the `src/iOS` directory and run `bundle install`.)
- Since _fastlane_ stores your provisioning profiles and certificates in a Git repository (`MATCH_REPO`), you need to create a new, empty repository if you haven't already. The profiles and certificates are protected by a password (`MATCH_PASSWORD`).
- When creating the Beta locally, _fastlane_ will make sure that your certificates and provisioning profiles are up-to-date.

### How to release a Beta locally

You'll need to obtain the values for the following parameter:

- `MATCH_REPO`: The URL to the Git repository that contains the provisioning profiles/certificates
- `MATCH_PASSWORD`: The password for encrypting/decrypting the provisioning profiles/certificates
- `FASTLANE_TEAM_ID`: The ID of the developer team at developer.apple.com
- `FASTLANE_USER`: The email address that is used to sign in to App Store Connect
- `FASTLANE_ITC_TEAM_ID`: The ID of the team at appstoreconnect.apple.com

In order to release a new Beta to the TestFlight testers, run

    % MATCH_REPO=<GIT_REPOSITORY_URL> \
      MATCH_PASSWORD=<MATCH_PASSWORD> \
      FASTLANE_TEAM_ID=<APPLE_DEVELOPER_TEAM_ID> \
      FASTLANE_USER=<APP_STORE_CONNECT_EMAIL> \
      FASTLANE_ITC_TEAM_ID=<APP_STORE_CONNECT_TEAM_ID> \
      bundle exec fastlane beta

## Source code structure

* iOS - Code specific to the iOS app
* Mac - Code specific to the Mac app (old, doesn't build anymore)
* Shared - Shared code (drawing code, OSM data structures, etc)
* Images - Images used for application elements (buttons, etc)
* png/poi/Maki/iD SVG POI - Icons used for map elements (POIs, etc)
* presets - The presets database copied from the iD editor

## Assets

The Go Map!! app icon was created by [@Binnette][5].

[1]: https://www.openstreetmap.org
[2]: download-on-the-app-store.png
[3]: https://itunes.apple.com/app/id592990211
[4]: https://testflight.apple.com/join/T96F9wYq
[5]: https://github.com/Binnette

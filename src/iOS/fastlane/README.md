fastlane documentation
================
# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```
xcode-select --install
```

Install _fastlane_ using
```
[sudo] gem install fastlane -NV
```
or alternatively using `brew cask install fastlane`

# Available Actions
## iOS
### ios pull_request_checks
```
fastlane ios pull_request_checks
```
Performs basic integration checks to be run before merging
### ios regenerate_app_icon
```
fastlane ios regenerate_app_icon
```
Re-generates the app icon from the base app_icon.png in the fastlane metadata directory

----

This README.md is auto-generated and will be re-generated every time [fastlane](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of fastlane can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

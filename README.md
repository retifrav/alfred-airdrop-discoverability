# AirDrop discoverability

[Alfred workflow](https://alfredapp.com/workflows/) for toggling [AirDrop](https://en.wikipedia.org/wiki/AirDrop) discoverability.

![AirDrop discoverability](https://raw.githubusercontent.com/retifrav/alfred-airdrop-discoverability/master/misc/airdrop-discoverability.png "Choosing AirDrop discoverability level")

## How does it work

Since there is no(?) API for toggling AirDrop discoverability, one has to manually click through controls in the Finder window. And that is what this workflow does - it automates clicking on Finder UI controls using [Mac OS Accessibility](https://support.apple.com/guide/mac-help/get-started-with-accessibility-features-mh35884/mac) functionality via [AppleScript](https://en.wikipedia.org/wiki/AppleScript).

To be able to do so (*find the right controls to click on*) the main script heavily relies on controls ordinals, such as `button 1 of splitter group 1 of window 1`, because there are no IDs/labels (*anymore?*), and so this entire logic is rather fragile and will likely "break" with one of the next Mac OS versions. When/if this happens, the script will need to be adjusted to correctly find the controls again.

## Installation

Download the latest version of the workflow itself and optionally its SHA-256 hash and PGP signature. Before [installing the workflow](https://www.alfredapp.com/blog/tips-and-tricks/tutorial-importing-and-setting-up-alfred-workflows/) it is recommended to verify its hash and signature:

``` sh
$ shasum -c ./airdrop-discoverability.alfredworkflow.sha256
$ gpg --verify ./airdrop-discoverability.alfredworkflow.sig
```

The signing PGP key is [here](https://decovar.dev/about/retif-public.asc).

## 3rd-party

- AirDrop icon from Apple Mac OS resources (*`/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AirDrop.icns`*);
- icons from Apple [SF Symbols](https://developer.apple.com/sf-symbols/) collection.

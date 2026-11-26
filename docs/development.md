# Development

## Requirements

- Xcode 27.2 or later with the iPadOS 27 SDK and an iPad simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), for example through `brew install xcodegen`.

## Commands

```sh
make            # list the commands
make test       # unit tests of the LinedKit package and the scripts, on the Mac
make test-app   # tests of the app with PencilKit and UIKit, in the simulator
make build      # generate the project and build for the simulator
make run        # build, install and launch in the simulator
```

`SIMULATOR` selects the simulator by name or identifier: `make run SIMULATOR="iPad Air 11-inch (M4)"`.

## Project file

`Lined.xcodeproj` is generated from `project.yml` and not checked in, so the project is defined by
text that can be reviewed and merged. Run `make project` after adding, moving or removing files and
before opening the project in Xcode. Build settings live in `Config/Lined.xcconfig`.

The repository carries a placeholder bundle identifier and no signing team. To run on a device or
upload a build, create `Config/Local.xcconfig`, which Git ignores:

```
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.lined
DEVELOPMENT_TEAM = ABCDE12345
```

## Layout

```
App/                 the app target: SwiftUI interface and the UIKit canvas
AppTests/            tests of the app target, run in the simulator
Packages/LinedKit/   model, storage, rendering, layout and ink bookkeeping, with tests
Config/              build settings
scripts/             release tooling, with tests
docs/                developer documentation
project.yml          project definition for XcodeGen
```

[architecture.md](architecture.md) explains the modules and the canvas, [storage.md](storage.md)
the format on disk and [testflight.md](testflight.md) how test builds reach an iPad.

## Tests

The package tests run on the Mac with Swift Testing and cover the model's invariants, the storage
round trips and recovery paths, the rendering of paper and PDF pages, the canvas geometry, and the
bookkeeping of ink and undo steps.
Logic belongs in the package so that it can be tested this way; the app target holds interface and
wiring.

The app tests run in the simulator with Swift Testing, hosted by the app, so they use the real
PencilKit and UIKit: how strokes are cut off at the edge of their page, which widths PencilKit
draws, what the canvas reports to the notebook, and how the paper follows the ink when a zoom
springs back. Run them with `make test-app`
before handing out a build.

Interface changes are checked in the simulator, in light and dark mode. Finger drawing is on by
default there, since the simulator has no Apple Pencil: one finger draws and two fingers scroll and
zoom. On a device the default is Apple Pencil only.

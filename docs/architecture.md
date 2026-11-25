# Architecture

Lined is a SwiftUI app with a small UIKit core for the page canvas. Everything that does not need
UIKit lives in a local Swift package, `Packages/LinedKit`, and is tested on the Mac.

## Modules

| Module | Purpose | May import |
| --- | --- | --- |
| `LinedModel` | The library tree, notebooks, pages and their invariants. Pure values. | Foundation |
| `LinedStorage` | Reads and writes the library and notebook packages on disk. | `LinedModel` |
| `LinedRendering` | Draws page backgrounds, paper and PDF, into bitmaps. | `LinedModel`, CoreGraphics |
| `LinedLayout` | Geometry of the canvas: page stack, ink window, render planning. | CoreGraphics |
| App target | Interface, PencilKit, and the wiring between the modules. | all of the above |

Dependencies point from the app to the package and never back. The package targets compile for
iPadOS and macOS; nothing in them touches UIKit, SwiftUI or PencilKit.

The app target is split by feature:

- `App/Library` shows folders and notebooks. `LibraryModel` is the only place that changes the library.
- `App/Notebook` opens one notebook. `NotebookSession` owns its pages, ink, undo history and saving.
- `App/Canvas` is the UIKit bridge that scrolls, zooms and draws the pages.
- `App/Covers` renders and caches the cover pictures of the library.

## Document model

A notebook is an ordered list of pages. A page has an identifier, a size in points and a background:
either a paper template or one page of an imported PDF. All positions on a page are in page points
with the origin at the top left.

Everything that belongs to a page is stored and addressed by the page's identifier, not by its
position. Ink is the first such layer. Further layers, such as recognised text or AI annotations
anchored to a region of a page, can be added as new files per page without touching the page list
or the ink. Identifiers are typed (`Identifier<Page>`, `Identifier<Notebook>`), so they cannot be
mixed up.

## Canvas

`PagedCanvasView` shows the pages as one vertical stack inside a single `UIScrollView`, which owns
scrolling and zooming. The content is laid out in page points and the scroll view's zoom scale is
the number of screen points per page point.

- **Virtualized pages.** Only the pages near the viewport have a view. Views are reused, so memory
  and work do not grow with the length of the document.
- **Ink.** Each page view holds a `PKCanvasView` that covers only the visible part of the page. It
  is sized like the viewport, counter-scaled against the scroll view and given the same zoom itself,
  so PencilKit renders strokes at screen resolution at every zoom level with bounded memory. While
  a pinch is in progress the canvas keeps its resolution and is brought to full sharpness when the
  pinch ends.
- **Backgrounds.** `PageBackgroundView` shows bitmaps rendered off the main thread. A base image
  covers the whole page at screen resolution up to a pixel budget. Beyond that budget, a detail image
  at screen resolution covers the visible part of the page. An image stays on screen until its
  replacement is ready, and images are aligned to the pixel grid, so text is neither blank nor
  blurred while zooming. `BackgroundRenderPlanner` decides what to render; it is plain geometry and
  unit-tested.
- **PDF.** Pages are drawn with CoreGraphics from the stored PDF file. Nothing is pre-rasterized, so
  import is fast and the page stays vector-sharp at any zoom.

Input follows the tool picker's convention: Apple Pencil draws and fingers scroll. With finger
drawing switched on, one finger draws and two fingers scroll and zoom.

## Undo

A notebook session has one `UndoManager`. The canvases record PencilKit's own undo steps in it
through the responder chain, so the toolbar buttons, the tool picker, system gestures and the
keyboard all act on the same history across pages. Undo steps belong to a canvas, so the pages
edited last keep their views while out of sight, and a page that gives up its view gives up its
undo steps.

## Saving

Ink is saved per page a moment after the last change, and immediately when the app leaves the
foreground or the notebook is closed. Structural changes, such as adding or deleting a page, are
written at once. The storage format is described in [storage.md](storage.md).

## Concurrency

The app target is isolated to the main actor by default. File access for an open notebook goes
through the `NotebookFiles` actor, covers through the `CoverStore` actor, and background rendering
through a small operation queue with cancellation. The package's rendering types are thread-safe
and `Sendable`.

## Rules

- Keep UIKit and PencilKit inside `App/Canvas` and the few notebook types that hold drawings.
  Interface code elsewhere is SwiftUI.
- New logic that can be expressed without UIKit goes into the package, with tests.
- The model never knows about files, and storage never knows about views.
- Persisted formats change only by the rules in [storage.md](storage.md).

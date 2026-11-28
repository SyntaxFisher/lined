# Architecture

Lined is a SwiftUI app with a small UIKit core for the page canvas. Everything that does not need
UIKit lives in a local Swift package, `Packages/LinedKit`, and is tested on the Mac.

## Modules

| Module | Purpose | May import |
| --- | --- | --- |
| `LinedModel` | The library tree, notebooks, pages, the drawing tools and their invariants. Pure values. | Foundation |
| `LinedStorage` | Reads and writes the library and notebook packages on disk. | `LinedModel` |
| `LinedRendering` | Draws page backgrounds, paper and PDF, into bitmaps. | `LinedModel`, CoreGraphics |
| `LinedLayout` | Geometry of the canvas: page stack, render planning, tool bar docking. | CoreGraphics |
| `LinedInk` | Which page a stroke belongs to, which pages changed, the undo history, and which shape a drawn line stands for. | `LinedLayout` |
| App target | Interface, PencilKit, and the wiring between the modules. | all of the above |

Dependencies point from the app to the package and never back. The package targets compile for
iPadOS and macOS; nothing in them touches UIKit, SwiftUI or PencilKit.

The app target is split by feature:

- `App/Library` shows folders and notebooks. `LibraryModel` is the only place that changes the library.
  Items are dragged within the app as `LibraryDragItem`, which only names the item; its content type
  is declared in `App/Info.plist`. Folders open when a drag rests on them or another finger taps them,
  so an item can travel into a subfolder in one drag. `App/Info.plist` also registers Lined for PDFs,
  so it appears in the share sheet; `SharedPDFImport` turns a shared PDF into a new notebook in the
  open folder, or adds its pages to the open notebook if the reader chooses so.
- `App/Notebook` opens one notebook. `NotebookSession` owns its pages, ink, undo history and saving.
- `App/Canvas` is the UIKit bridge that scrolls, zooms and draws the pages.
- `App/Tools` is the floating tool bar with the options of each tool.
- `App/Covers` renders and caches the cover pictures of the library.

## Document model

A notebook is an ordered list of pages. A page has an identifier, a size in points and a background:
either a paper template or one page of an imported PDF. Paper pages are A4; PDF pages keep the
size of their PDF page, also when a PDF is imported into an existing notebook. All positions on a
page are in page points with the origin at the top left.

Everything that belongs to a page is stored and addressed by the page's identifier, not by its
position. Ink is the first such layer. Further layers, such as recognised text or AI annotations
anchored to a region of a page, can be added as new files per page without touching the page list
or the ink. Identifiers are typed (`Identifier<Page>`, `Identifier<Notebook>`), so they cannot be
mixed up.

## Canvas

`PagedCanvasView` shows the pages as one vertical stack. A single `PKCanvasView` is the scroll view
of the whole notebook, so scrolling, zooming and ink rendering are PencilKit's own and behave like
they do in every other app. The canvas draws in document points: page points magnified twice and
offset by the place of the page in the stack. PencilKit draws no even line thinner than 0.5 of its
points, so the magnification lets the finest pen draw lines of half that width on the page. Tool
widths are set in page points and doubled for PencilKit. Its zoom scale is the number of screen
points per document point, and it ends at ten, which is as far as PencilKit magnifies a canvas.

- **Virtualized pages.** Only the pages near the viewport have a background view. Views are reused,
  so memory and work do not grow with the length of the document. A view appears half a viewport
  before its page comes into sight and goes only one and a half viewports after it has left, and
  never while a zoom springs back, so pages next to the viewport stay in place while zooming.
- **Virtualized ink.** The canvas holds only the strokes of the pages near the viewport. A page's
  stored ink is asked for before the page scrolls into view and given up when the page is far away,
  with a gap between the two distances so that a page does not load and unload while the view moves
  back and forth. Arriving ink is added to what the canvas holds. Taking ink out means putting the
  rest together anew, so while the view scrolls, pages give their ink up several at a time. The ink
  in the canvas is never replaced while a tool is in use, while the ink settles after it or while a
  pinch is in progress; what arrives meanwhile waits.
- **Pages of strokes.** A stroke belongs to the page it starts on, or to the nearest page when it
  starts between two. Moving ink between page points and document points only changes a stroke's
  transform, which scales its line along, so strokes keep their identity and their masks.
- **Ink ends at the page.** A stroke that is drawn, moved or pasted across the edge of its page is
  split there once the tool has lifted: it becomes one stroke on each page it draws on, each with a
  mask that covers its line on that page, and what it draws beside the pages is dropped. The parts
  of a stroke are one undo step. Every stroke therefore lies inside one page, which is what a page
  stores, exports and shows in its thumbnail. A stroke with a mask counts as starting where its
  path first enters the mask, so each part belongs to the page it lies on.
- **Backgrounds.** `PageBackgroundView` shows bitmaps rendered off the main thread, beneath the ink.
  A base image covers the whole page at screen resolution up to a pixel budget. Beyond that budget,
  a detail image at screen resolution covers the visible part of the page. An image stays on screen
  until its replacement is ready, and images are aligned to the pixel grid, so text is neither blank
  nor blurred while zooming. `BackgroundRenderPlanner` decides what to render; it is plain geometry
  and unit-tested.
- **Desk.** `DeskView` lies above the ink and covers everything around the pages near the viewport
  with plain rectangles, so a stroke that is being drawn ends at the edge of the paper. `Desk` works
  the rectangles out; it is plain geometry and unit-tested.
- **Zoom.** The page backgrounds and the desk are scaled with the canvas's zoom. When a pinch goes
  past the zoom limits, the canvas springs back with an animation of the view that holds the ink;
  the backgrounds and the desk take that animation over, so paper and ink move together.
- **PDF.** Pages are drawn with CoreGraphics from the stored PDF file. Nothing is pre-rasterized, so
  import is fast and the page stays vector-sharp at any zoom.

Only Apple Pencil draws; fingers scroll and zoom. The Simulator has no Apple Pencil, so there one
finger draws and two fingers scroll and zoom.

These properties of PencilKit shape the canvas:

- Reading the ink of a canvas takes time with every stroke it holds, however little of it changed.
  The canvas reads its ink once the writing pauses, not after every stroke, and keeps the number of
  pages whose ink it holds small.
- A canvas draws a stroke it already shows again only when the stroke's identity changes. The parts
  of a split stroke are therefore new strokes.
- PencilKit's erasers take whole strokes or leave slivers of a line beside their path. The canvas
  therefore erases itself: once the eraser covers a pixel of a stroke's ink, it cuts a piece about
  its own diameter out of the stroke across the line's whole width, and the remaining pieces
  become new strokes with round ends like the line's own. The line PencilKit draws through a point
  is twice as wide as the size it keeps for the point exceeds two, which tells whether a pixel is
  covered.
- PencilKit hands out a path's points slowly, and testing them against the mask of a stroke cut at
  a page's edge is slow too. While the eraser is chosen, the canvas reads the points of its strokes
  in the background, so that erasing only calculates.
- PencilKit drops a lasso selection whenever its view is resized, so the canvas keeps its size when
  a keyboard appears.
- PencilKit takes the focus while strokes are selected and accepts typed text there, which would
  bring up the keyboard. The canvas takes the focus back; the selection and its menu stay.
- PencilKit selects strokes and opens its edit menu on a tap or a long press with any tool. These
  gestures are switched on only for the lasso, so a resting hand does nothing with the other tools.

## Tools

`ToolSettings` in the model holds the selected tool and what each tool remembers: colour and width
of the pen, and the width of the eraser. The pen draws an even line. The eraser's size is in screen
points, so it erases as much of the screen at any zoom; `StrokeEraser` in `LinedInk` decides which
points of a line it sweeps over, `InkEraser` cuts the strokes with it, and `EraserIndicator` outlines
it under the touch. The app maps the settings to PencilKit tools in one place. The settings and the
edge the tool bar is docked to are saved as preferences of the app, not of a notebook.

`FloatingToolBar` replaces the system tool picker. It floats above the canvas, unfolds the options
of the selected tool in place and can be dragged to any edge of the screen; `DockEdge` picks the edge
nearest to where the bar is let go. The bar mostly floats over paper, which stays light, so in dark
mode its glass is darkened until its light icons and the colours of dark ink stand out. A double
tap on Apple Pencil does what the user chose in the system settings.

## Shapes

A line that the pen draws and then holds still at its end for half a second becomes the shape it
comes closest to. `ShapeRecognizer` in `LinedInk` decides which: a straight line, a few straight
sides through corners, an ellipse or a polygon, with circles, rectangles and squares recognised as
such and nearly horizontal or vertical sides made exactly so. A closed line is a polygon only if
its sides are straight; a round line, however uneven, is an ellipse. A line that follows none of
these closely stays as it was drawn, and so does one too short to be more than writing.

`PenHoldGestureRecognizer` watches the pen beside PencilKit's own drawing gesture without ever
recognising, so the touch stays with PencilKit. When a held line is a shape, the canvas switches
PencilKit's drawing gesture off and on again, which ends the stroke under the pen without leaving it
in the ink, and adds the shape as a stroke of the pen's ink and width. From there it is ink like any
other: one step to undo, split at the edge of its page, erased and selected like a drawn stroke.

While the pen stays down after the shape has snapped, it pulls at the shape: the shape turns and
grows about its anchor, the start of an open line or the middle of a closed shape, so that it
follows the pen. Each move replaces the shape's stroke; the step to undo is the shape as the pen
leaves it.

The path of a stroke is a uniform cubic spline. The shape's stroke has control points a few points
apart along its outline and three in each corner, where the spline then turns sharply. An ellipse
has at least 72 points however small it is; with fewer, the ends of the spline stand out of the line.

Nothing but the stroke is stored for a shape. `RecognizedShape` reads a shape back from the control
points of a stroke, which only a stroke made from a shape has in that form and only while it is
whole: one that was cut by the eraser or at the edge of a page is plain ink. A tap of the pen on the
line of such a stroke shows its handles in `ShapeHandlesView`, a knob on each corner or on the ends
of an ellipse's axes, above the canvas. Dragging a knob replaces the stroke with the changed shape,
as one step to undo. PencilKit draws a dot for the tap, which the canvas takes out again. The handles
go when the pen draws, erases or changes the tool.

## Undo

A notebook keeps its own undo history, `InkHistory`, because the ink of a page leaves the canvas
when the page is far away and an undo step must still reach it. The canvas tells the session which
pages changed; each report is one step with the ink of those pages before and after.

The canvas reports once its ink has settled, a moment after the tool has lifted. After plain
writing it looks at the new strokes only, which lie on top of the ink it reported before, and
reports each of them as a step of its own. An eraser or a lasso changes the ink many times while it
moves; then the canvas compares all its strokes with what it reported last and reports the result
once, so it is one step. Before the session undoes, redoes or saves, it asks the canvas for what is
still waiting to be reported.

Undoing puts the earlier ink back into the store and, where the page is loaded, into the canvas.
The steps of a deleted page are forgotten with it.

`NotebookUndoManager` is the undo manager the canvas and PencilKit find through the responder chain.
It records nothing and passes undoing on to the session, so the toolbar buttons, the system's
gestures, the canvas's own double tap with two fingers and the keyboard all act on the same history.

## Saving

Ink is saved per page at most a second after a change, also while writing continues, and immediately
when the app leaves the foreground or the notebook is closed. Structural changes, such as adding or
deleting a page, are written at once. The storage format is described in [storage.md](storage.md).

## Concurrency

The app target is isolated to the main actor by default. File access for an open notebook goes
through the `NotebookFiles` actor, covers through the `CoverStore` actor, and background rendering
through a small operation queue with cancellation. The package's rendering types are thread-safe
and `Sendable`.

## Rules

- Keep UIKit and PencilKit inside `App/Canvas` and the few notebook types that hold drawings.
  Interface code elsewhere is SwiftUI.
- New logic that can be expressed without UIKit goes into the package, with tests. PencilKit does
  not run in the package's tests; code that handles strokes there is generic over `InkStroke`.
- Behaviour that depends on PencilKit or UIKit, such as how strokes are split or how the canvas
  reports and zooms, is covered by the app tests in `AppTests`.
- The model never knows about files, and storage never knows about views.
- Persisted formats change only by the rules in [storage.md](storage.md).

# Storage

Lined stores everything as plain files in the app's Application Support directory. There is no
database: the data is a small catalog plus one self-contained directory per notebook.

```
Library/
  library.json                      catalog of folders and notebooks
  Notebooks/
    <notebook-id>.lined/            one package per notebook
      notebook.json                 ordered pages: size and background
      view-state.json               where the reader left off
      drawings/<page-id>.drawing    ink of one page (PencilKit data)
      sources/<source-id>.pdf       imported PDF files, unmodified
```

Cover pictures are derived data and live in the caches directory.

## Why files

- **Robust.** Every write is atomic, and a page's ink is its own file. A crash can lose at most the
  last moments of one page and can never damage another page or notebook.
- **Simple to evolve.** JSON files carry a format version. New kinds of page content become new
  files in the package, next to the ones that exist.
- **Ready for sync and export.** A notebook is one directory that can be copied, shared or synced
  as a unit, and the original PDF is kept byte for byte.
- **Fast.** Opening a notebook reads the page list only. Ink and PDF pages load as they scroll into view.

## Files

`library.json` holds the folder tree and the title, folder and dates of each notebook:

```json
{
  "formatVersion": 1,
  "folders": [{ "id": "…", "name": "Semester 3", "parentID": "…", "createdAt": "…", "modifiedAt": "…" }],
  "notebooks": [{ "id": "…", "title": "Analysis", "folderID": "…", "createdAt": "…", "modifiedAt": "…" }]
}
```

`notebook.json` holds the pages in order. Sizes are in points:

```json
{
  "formatVersion": 1,
  "pages": [
    { "id": "…", "size": { "width": 595, "height": 842 }, "background": { "kind": "paper", "template": "lined" } },
    { "id": "…", "size": { "width": 612, "height": 792 }, "background": { "kind": "pdf", "source": "…", "pageIndex": 0 } }
  ]
}
```

Timestamps are ISO 8601 with fractional seconds. Identifiers are UUIDs. An item in the library root
has no `parentID` or `folderID`, and a page without ink has no drawing file.

## Consistency

The catalog and the packages are written separately, so the app brings them in line at launch:

- A catalog entry without a package is dropped.
- A package without a catalog entry is adopted into the library root as a recovered notebook.
- A notebook is created in a temporary directory and moved into place when complete, so a
  half-written package never appears.
- Deleting removes the package first and the catalog entry second.
- An unreadable catalog is set aside, not overwritten, and rebuilt from the packages.
- Ink that cannot be decoded is set aside and the page opens empty.

## Changing the format

- A file whose `formatVersion` is higher than the app understands is refused, never rewritten.
- Additive changes, such as a new optional field or a new file in the package, keep the version.
- A change that older builds would misread raises the version and comes with a migration and tests.
- Per-page content is keyed by page identifier, never by page number.

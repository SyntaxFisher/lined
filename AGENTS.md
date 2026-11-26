# Agent instructions

- Lined is a native iPadOS note-taking app with AI integrated into Apple Pencil interaction. The README describes the product for users; keep implementation and release details in `docs/`.
- The AI runs on each user's own ChatGPT plan through Sign in with ChatGPT. Never ship shared API keys or other credentials in the app or the repository.
- Use conventional commits.

## Commands

- `make test` runs the unit tests of the `LinedKit` package and of the scripts on the Mac.
- `make build` generates `Lined.xcodeproj` from `project.yml` with XcodeGen and builds for the iPad simulator.
- `make run` builds, installs and launches the app in the simulator. `SIMULATOR` selects it by name or identifier.
- The project file is generated and ignored by Git. Run `make project` after adding, moving or removing files.

## Architecture

- Read `docs/architecture.md` before changing the structure and `docs/storage.md` before changing anything that is saved.
- `Packages/LinedKit` holds the model, storage, rendering and canvas geometry without UIKit, SwiftUI or PencilKit. Logic that fits there goes there, with tests.
- The app target is SwiftUI. UIKit and PencilKit stay in `App/Canvas` and the notebook types that hold drawings.
- `LibraryModel` is the only place that changes the library, `NotebookSession` the only place that changes an open notebook.
- Page content is stored per page and keyed by page identifier, in page points with the origin at the top left. New kinds of content become new files in the notebook package.
- Saved formats are versioned. Follow the rules in `docs/storage.md` when changing them.
- Verify interface changes in an iPad simulator, where finger drawing stands in for Apple Pencil.

## Releases

- Internal TestFlight builds are described in `docs/testflight.md`. Each upload needs the owner's explicit consent for that build. They are internal-only and never submitted, published or tagged.

## Git workflow

- Squash-merge feature work locally into `main`, with focused commits describing the final changes.
- Push only `main` and release tags; keep working branches local.
- This repository is public. Keep public documentation general; private infrastructure and environment details must stay out of Git history. Reports, screenshots, videos and logs stay outside it, and committed files and messages carry no names, e-mails, account ids, usage data, local paths or machine details. Review outgoing files and commits for credentials, private data and machine-specific artifacts before committing or publishing.
- The maintainer's GitHub noreply identity is the only author and committer. Commit messages carry no `Co-Authored-By`, session or other attribution trailers.

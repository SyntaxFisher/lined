# Agent instructions

- Lined is a native iPadOS note-taking app with AI integrated into Apple Pencil interaction. The README describes the product for users; keep implementation and release details in `docs/`.
- The AI runs on each user's own ChatGPT plan through Sign in with ChatGPT. Never ship shared API keys or other credentials in the app or the repository.
- Use conventional commits.

## Git workflow

- Squash-merge feature work locally into `main`, with focused commits describing the final changes.
- Push only `main` and release tags; keep working branches local.
- This repository is public. Keep public documentation general; private infrastructure and environment details must stay out of Git history. Reports, screenshots, videos and logs stay outside it, and committed files and messages carry no names, e-mails, account ids, usage data, local paths or machine details. Review outgoing files and commits for credentials, private data and machine-specific artifacts before committing or publishing.
- The maintainer's GitHub noreply identity is the only author and committer. Commit messages carry no `Co-Authored-By`, session or other attribution trailers.

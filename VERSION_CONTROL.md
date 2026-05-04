# Version Control Guide

This repository uses Git with `main` as the stable branch and `development` for day-to-day work.

## Daily commit workflow

1. Review changes:
   - `git status`
   - `git diff`
2. Stage files:
   - `git add <file>` for specific files, or `git add .` for all tracked updates.
3. Commit with a clear message:
   - `git commit --trailer "Co-authored-by: Cursor <cursoragent@cursor.com>" -m "Short action-focused message"`
4. Push branch:
   - `git push`

## Create a branch before risky changes

Use a feature branch whenever you are trying a large refactor or uncertain change:

1. Start from latest development:
   - `git checkout development`
   - `git pull`
2. Create and switch:
   - `git checkout -b feature/<short-name>`
3. Work and commit normally.
4. Push the branch:
   - `git push -u origin feature/<short-name>`

## Revert safely when needed

### Undo uncommitted local edits
- Discard file changes: `git restore <file>`
- Unstage a file: `git restore --staged <file>`

### Revert a committed change (safe for shared branches)
- `git log --oneline`
- `git revert <commit-hash>`
- `git push`

### Inspect previous states
- `git log --oneline --graph --decorate`
- `git checkout <commit-hash>` (detached view only)
- Return to branch: `git checkout development`

## Recommended branch policy

- `main`: stable snapshots/releases only.
- `development`: active integration branch.
- `feature/*`: short-lived task branches merged into `development`.
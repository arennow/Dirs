# Updating the Draft Release

This directory contains the release notes for the next version of Dirs.

## Files

- `DRAFT_RELEASE_NOTES.md` - The formatted release notes ready to be used
- `update-draft-release.sh` - A script that can update the draft release on GitHub (requires `gh` CLI and appropriate permissions)

## Manual Update Process

If you have access to the GitHub repository with release management permissions:

1. Go to https://github.com/arennow/Dirs/releases
2. Find the draft release
3. Click "Edit release"
4. Copy the contents of `DRAFT_RELEASE_NOTES.md` (excluding the first line "# Draft Release Notes for Next Version")
5. Paste into the release description field
6. Click "Save draft" (do NOT publish)

## Using the Script

If you have the `gh` CLI installed and configured:

```bash
./update-draft-release.sh
```

This will automatically find the draft release and update its description.

## Changes Described

The release notes describe the addition of node date support (creation and modification timestamps) that was added since version 0.11.0.

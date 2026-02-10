#!/bin/bash
# Script to update the draft release notes
# This script requires gh CLI and appropriate GitHub permissions

set -e

RELEASE_NOTES=$(cat <<'EOF'
## New Features

- **Node date support**: Access creation and modification timestamps for any filesystem node (files, directories, symlinks, and Finder aliases).
  - `Node.date(of:)` - Get creation or modification date from any node
  - `FilesystemInterface.date(of:at:)` - Get dates at the filesystem interface level
  - New `NodeDateType` enum with `.creation` and `.modification` cases
  - Works with broken symlinks - they retain their own date metadata even when their target doesn't exist

## Improvements

- **Modification dates automatically updated**: File modification timestamps are now automatically updated when file contents are changed via `replaceContents()` or `appendContents()`.

## API Updates

- `Node.date(of:)` method added to all node types
- `FilesystemInterface.date(of:at:)` added to protocol
- `NodeDateType` enum added with `.creation` and `.modification` cases
- Mock filesystem now tracks creation and modification dates for all nodes

**Full Changelog**: https://github.com/arennow/Dirs/compare/0.11.0...main
EOF
)

echo "Updating draft release notes..."

# Find the draft release
DRAFT_RELEASE=$(gh release list --json isDraft,tagName,id --jq '.[] | select(.isDraft == true) | .tagName' | head -1)

if [ -z "$DRAFT_RELEASE" ]; then
    echo "Error: No draft release found"
    exit 1
fi

echo "Found draft release: $DRAFT_RELEASE"
echo "Updating release notes..."

# Update the release notes
gh release edit "$DRAFT_RELEASE" --notes "$RELEASE_NOTES"

echo "Draft release notes updated successfully!"

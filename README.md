# Dirs

A Swift library that provides a high-level, type-safe abstraction over filesystem interactions. It ships two implementations of the same `FilesystemInterface` protocol—one backed by the real filesystem and one backed by an in-memory mock—so that the code you write against it is trivially testable without ever touching disk.

## Installation

```swift
// Package.swift
.package(url: "https://github.com/arennow/Dirs.git", from: "<version>")
```

---

## Real vs. Mock Filesystem

The library's central design principle is the **parity guarantee**: every observable behavior of `RealFSInterface` (the on-disk implementation) is reproduced exactly by `MockFSInterface` (the in-memory implementation). This means you can write your application code against the `FilesystemInterface` protocol, swap in a `MockFSInterface` in tests, and have full confidence that you are exercising the real code paths without any disk I/O.

```swift
// Production
let fs: any FilesystemInterface = RealFSInterface()

// Tests
let fs: any FilesystemInterface = MockFSInterface()
```

Both types satisfy the same protocol, so your functions never need to know which one they are holding.

---

## Platforms

Tests are run in CI on macOS and Ubuntu Linux. Windows support is in beta. Not all features are available on every platform; see the table below.

| Feature | macOS | Linux | Windows | iOS / tvOS / watchOS / visionOS |
|---|:---:|:---:|:---:|:---:|
| Core CRUD | ✅ | ✅ | ✅ | ✅ |
| Symlinks | ✅ | ✅ | ✅ | ✅ |
| Extended attributes | ✅ | ✅ | ❌ | ✅ |
| Special files (FIFOs, sockets, devices) | ✅ | ✅ | ❌ | ✅ |
| Finder aliases | ✅ | ❌ | ❌ | ✅ |

Minimum deployment targets: macOS 10.15, iOS 13, tvOS 13, watchOS 6, visionOS 1.

---

## Core Concepts

### `Node` and its concrete types

Every filesystem object is represented by a type that conforms to the `Node` protocol. Nodes carry a reference to the `FilesystemInterface` they belong to and a `FilePath` describing their location.

| Type | Represents |
|---|---|
| `Dir` | A directory |
| `File` | A regular file |
| `Symlink` | A symbolic link |
| `FinderAlias` | A macOS Finder alias *(macOS / Darwin only)* |
| `Special` | A FIFO, socket, or device node *(macOS / Linux only)* |

`Symlink` and `FinderAlias` additionally conform to `ResolvableNode`, which adds a `destination` property (the raw link target) and a `resolve()` method that follows the link and returns the target `Node`.

### `FilesystemInterface`

`FilesystemInterface` is the protocol that both `RealFSInterface` and `MockFSInterface` conform to. It handles absolute-path operations: creating, reading, updating, deleting, moving, and copying nodes, as well as platform-specific features such as extended attributes and Finder aliases.

In practice, you will rarely call `FilesystemInterface` methods directly. Most everyday work is done through the instance methods on `Node`-conforming types, which delegate to the interface under the hood.

### `IntoFilePath`

Functions that accept a path take `some IntoFilePath` rather than a bare `FilePath`. `String`, `URL`, `FilePath`, and every `Node`-conforming type all satisfy this protocol, so you can pass whichever representation you already have.

---

## Features

### Creating nodes

```swift
let dir  = try fs.createDir(at: "/tmp/work")
let file = try dir.createFile(at: "notes.txt")   // relative to dir
let link = try fs.createSymlink(at: "/tmp/link", to: "/tmp/work")
```

### Reading and writing files

```swift
try file.replaceContents("Hello, world!")
let text = try file.stringContents()   // "Hello, world!"

try file.appendContents("\nLine two.")
let size = try file.size()             // in bytes
```

### Directory listing

```swift
let children = try dir.children()          // does not follow symlinks / aliases
let resolved = try dir.resolvedChildren()  // follows all symlinks and aliases

// Children groups nodes by type:
// children.dirs, children.files, children.symlinks,
// children.finderAliases (Darwin), children.specials (Unix)
```

### Moving, renaming, copying, and deleting

```swift
try file.rename(to: "renamed.txt")
try file.move(to: "/tmp/archive/renamed.txt")   // absolute destination
try fs.copyNode(from: file, to: "/tmp/backup/renamed.txt")
try file.delete()
```

### Extended attributes *(macOS, Linux, iOS, tvOS, watchOS, visionOS)*

```swift
#if XATTRS_ENABLED
try file.setExtendedAttribute(named: "user.comment", to: "first draft")
let comment = try file.extendedAttributeString(named: "user.comment") // "first draft"
let names   = try file.extendedAttributeNames()   // Set<String>
try file.removeExtendedAttribute(named: "user.comment")
#endif
```

### Finder aliases *(macOS / Darwin only)*

```swift
#if FINDER_ALIASES_ENABLED
let alias  = try fs.createFinderAlias(at: "/tmp/alias", to: "/tmp/work")
let target = try alias.resolve()        // any Node pointing at /tmp/work
#endif
```

### Well-known directories

```swift
let home    = try fs.lookUpDir(.home)
let temp    = try fs.lookUpDir(.temporary)
let unique  = try fs.lookUpDir(.uniqueTemporary)  // always a fresh directory
```

---

## Examples

### List all children whose name begins with a given prefix

```swift
func children(of dir: Dir, startingWith prefix: String) throws -> [any Node] {
    let children = try dir.children()
    let allNodes: [any Node] = children.dirs + children.files + children.symlinks
    return allNodes.filter { $0.path.lastComponent?.string.hasPrefix(prefix) == true }
}
```

### Report the length of every extended attribute on a file

```swift
#if XATTRS_ENABLED
func xattrLengths(of file: File) throws -> [String: Int] {
    let names = try file.extendedAttributeNames()
    var result = [String: Int]()
    for name in names {
        let data = try file.extendedAttribute(named: name)
        result[name] = data?.count ?? 0
    }
    return result
}
#endif
```

### Collect all `.swift` files under a directory, recursively

```swift
func swiftFiles(in dir: Dir) throws -> [File] {
    var results = [File]()
    let children = try dir.resolvedChildren()
    for file in children.files where file.path.extension == "swift" {
        results.append(file)
    }
    for subdir in children.dirs {
        results += try swiftFiles(in: subdir)
    }
    return results
}
```

---

## License

See [LICENSE](LICENSE).

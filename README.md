# Dirs

A Swift library that provides a high-level, type-safe abstraction over filesystem interactions. It ships two implementations of the same `FilesystemInterface` protocol—one backed by the real filesystem and one backed by an in-memory mock—so that the code you write against it is trivially testable without ever touching the disk.

## Installation

```swift
// Package.swift
.package(url: "https://github.com/arennow/Dirs.git", from: "0.15.0")
```

---

## Real vs. Mock Filesystem

The library's central design principle is its **parity guarantee**: every observable behavior of `RealFSInterface` (the on-disk implementation) is reproduced exactly by `MockFSInterface` (the in-memory implementation). This means you can write your application code against the `FilesystemInterface` protocol, swap in a `MockFSInterface` in tests, and have full confidence that you are exercising the real code paths without any disk I/O.

```swift
// Production
let fs: any FilesystemInterface = RealFSInterface()

// Tests
let fs: any FilesystemInterface = MockFSInterface()
```

Different platforms' behavior may differ (_e.g._, Linux's implementation of extended attributes is much more limited than Darwin's), but the two filesystem interfaces should always act the same on any given platform.

This library's test suite runs fully on both real and mock interfaces to ensure that there's no drift between the two. Any observable difference between real and mock interfaces is a bug and should be reported (with a reproducible test case).

---

## Platforms

Tests are run in CI on macOS and Ubuntu Linux. Windows support is in beta. Darwin is the umbrella term for all of Apple's operating systems, including macOS, iOS, tvOS, watchOS and visionOS.

| Feature | Darwin | Linux | Windows |
|---|:---:|:---:|:---:|
| Core CRUD | ✅ | ✅ | ✅ |
| Symlinks | ✅ | ✅ | ✅ |
| Finder aliases | ✅ | ❌ | ❌ |
| Extended attributes | ✅ | ✅ | ❌ |
| Special files (FIFOs, sockets, devices) | ✅ | ✅ | ❌ |

Minimum deployment targets: macOS 10.15, iOS 13, tvOS 13, watchOS 6, visionOS 1.

---

## Core Concepts

### `Node` and its concrete types

Every filesystem object is represented by a lightweight struct that conforms to the `Node` protocol. Nodes carry a reference to the `FilesystemInterface` they belong to and a `FilePath` describing their location.

| Type | Represents |
|---|---|
| `Dir` | A directory |
| `File` | A regular file |
| `Symlink` | A symbolic link |
| `FinderAlias` | A macOS Finder alias *(Darwin only, though seldom encountered outside of macOS)* |
| `Special` | A FIFO, socket, or device node – basically a catchall *(Darwin / Linux only)* |

`Symlink` and `FinderAlias` additionally conform to `ResolvableNode`, which adds a `destination` property (the raw link target) and a `resolve()` method that follows the immediate resolvable and any others it encounters along the way and returns the target `Node` (the real, non-resolvable node that the chain ultimately refers to).

### `FilesystemInterface`

`FilesystemInterface` is the protocol that both `RealFSInterface` and `MockFSInterface` conform to. It handles absolute-path operations: creating, reading, updating, deleting, moving, and copying nodes, as well as platform-specific features such as extended attributes and Finder aliases.

In practice, you will rarely call `FilesystemInterface` methods directly. Most everyday work is done through the instance methods on `Node`-conforming types, which delegate to the interface under the hood.

### `IntoFilePath`

Functions that accept a path take `some IntoFilePath` rather than a bare `FilePath`. `String`, `URL`, `FilePath`, and every `Node`-conforming type all satisfy this protocol, so you can pass whichever representation you already have.

---

## Features

### Creating nodes

```swift
let dir: Dir = // some Dir
let file: File = try dir.createFile(at: "notes.txt") // relative to `dir`
let link: Symlink = try dir.createSymlink(at: "link", to: "/tmp/work")
```

### Reading and writing files

```swift
try file.replaceContents("Hello, world!")
let text = try file.stringContents() // "Hello, world!"

try file.appendContents("\nLine two.")
let size = try file.size() // in bytes
```

### Directory listing

```swift
let children: Children = try dir.children() // does not follow symlinks / aliases
let resolved: Children = try dir.resolvedChildren() // follows all symlinks and aliases
```

`Children` groups nodes by type:
`.dirs`, `.files`, `.symlinks`,
`.finderAliases` (Darwin), `.specials` (Darwin and Linux)

But you can also access them all at once:
```swift
let allChildren: some Sequence<any Node> = children.all
```

### Moving, renaming, copying, and deleting

```swift
try file.rename(to: "renamed.txt")
try file.move(to: "/tmp/archive/renamed.txt")   // absolute destination
try fs.copyNode(from: file, to: "/tmp/backup/renamed.txt")
try file.delete()
```

Note that `rename` and `move` are `mutating` and change the internally stored path of the receiver.

### Extended attributes *(Darwin and Linux)*

```swift
try file.setExtendedAttribute(named: "user.comment", to: "first draft")
let comment = try file.extendedAttributeString(named: "user.comment") // "first draft"
let names = try file.extendedAttributeNames()
try file.removeExtendedAttribute(named: "user.comment")
```

### Finder aliases *(Darwin only)*

```swift
#if FINDER_ALIASES_ENABLED
let alias: FinderAlias = try fs.createFinderAlias(at: "/tmp/alias", to: "/tmp/work")
let target: any Node = try alias.resolve()
#endif
```

### Well-known directories

```swift
let home = try fs.lookUpDir(.home)
let temp = try fs.lookUpDir(.temporary)
let unique = try fs.lookUpDir(.uniqueTemporary)  // always a fresh directory
```

---

## Examples

### List all immediate children whose name begins with a given prefix

```swift
func children(of dir: Dir, startingWith prefix: String) throws -> [any Node] {
    try dir.children().all.filter { childNode: any Node in
        // `Node.name` is a plain `String` derived from the internal `path: FilePath`
        childNode.name.hasPrefix(prefix)
    }
}
```

### Collect all `.swift` files under a directory recursively

```swift
func swiftFiles(in dir: Dir) throws -> [File] {
    try dir.allDescendantFiles.filter { childFile: File in
        // Here we access `path` directly to take advantage of its filename extension logic
        childFile.path.extension == "swift"
    }
}
```

---

## A note on `FilePath`

The currency type for paths in Dirs is `FilePath` – specifically the one vended by Apple's `SystemPackage` [SPM module](https://github.com/apple/swift-system). Darwin OSes _also_ vend a type called `FilePath`, _also_ from a module called `System`. The two are effectively the same in terms of API and capabilities, but they aren't interchangeable because Swift sees them as different types. Dirs uses the SPM module version becuase it's also available on non-Darwin platforms. This is a bit of an awkward arrangement, but there's some movement to merge the two into a single definition in the Swift standard library, which would solve this problem (at least for clients using new versions of the stdlib).
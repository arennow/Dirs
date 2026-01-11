//
//  FSInterface.swift
//  Dirs
//
//  Created by Aaron Rennow on 2026-01-10.
//

/// An enum wrapper for `FilesystemInterface` conformers that reduces the
/// storage size of `Node` conformers to fit within the inline buffer of
/// an `any Node` existential (24 bytes), avoiding heap allocations.
///
/// Without this, each `Node` conformer stores `any FilesystemInterface`
/// (40 bytes) + `FilePath` (~8 bytes) = ~48 bytes, which exceeds the
/// existential's 24-byte inline buffer and requires heap allocation.
///
/// With this enum, `Node` conformers store:
///  `FSInterface` (9 bytes in size; 16 in stride) +
///  `FilePath` (8 bytes) =
///  24 bytes (in stride), fitting inline.
///
/// See the memory layout tests in `DirsTests.swift` for verification.
enum FSInterface: Equatable, Sendable {
	case real(RealFSInterface)
	case mock(MockFSInterface)

	/// Extracts the underlying `FilesystemInterface` conformer as an existential.
	var wrapped: any FilesystemInterface {
		switch self {
			case .real(let r): r
			case .mock(let m): m
		}
	}
}

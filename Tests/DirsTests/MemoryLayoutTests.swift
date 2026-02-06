@testable import Dirs
import Foundation
import SystemPackage
import Testing

/// These tests verify that Node conformers fit within the inline buffer of an
/// `any Node` existential (24 bytes), avoiding heap allocations.
/// See the documentation comment on `FSInterface` in Sources/Dirs/FSInterface.swift
/// for the full explanation of this optimization.
@Suite
struct MemoryLayoutTests {
	@Test
	func nodeElementCompontentSizes() {
		#expect(MemoryLayout<FSInterface>.size == 9)
		#expect(MemoryLayout<FSInterface>.stride == 16)
		#expect(MemoryLayout<FilePath>.size == 8)
	}

	@Test
	func dirFitsInExistentialInlineBuffer() {
		#expect(MemoryLayout<Dir>.size <= 24)
	}

	@Test
	func fileFitsInExistentialInlineBuffer() {
		#expect(MemoryLayout<File>.size <= 24)
	}

	@Test
	func symlinkFitsInExistentialInlineBuffer() {
		#expect(MemoryLayout<Symlink>.size <= 24)
	}

	#if FINDER_ALIASES_ENABLED
		@Test
		func finderAliasFitsInExistentialInlineBuffer() {
			#expect(MemoryLayout<FinderAlias>.size <= 24)
		}
	#endif
}

import SystemPackage

public protocol Node: IntoFilePath, Hashable, Sendable {
	var fs: any FilesystemInterface { get }
	var path: FilePath { get }

	mutating func move(to destination: some IntoFilePath) throws
}

public extension Node {
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.fs.isEqual(to: rhs.fs) && lhs.path == rhs.path
	}

	func into() -> FilePath { self.path }
}

public extension Node {
	var name: String {
		self.path.lastComponent?.string ?? ""
	}

	var parent: Dir {
		get throws {
			try Dir(fs: self.fs, path: self.path.removingLastComponent())
		}
	}

	func delete() throws {
		try self.fs.deleteNode(at: self)
	}

	func realpath() throws -> FilePath {
		try self.fs.realpathOf(node: self)
	}

	func pointsToSameNode(as other: some Node) throws -> Bool {
		try self.realpath() == other.realpath()
	}

	func descendantPath(from other: some Node) throws -> FilePath {
		var nndError: NodeNotDescendantError {
			NodeNotDescendantError(putativeAncestor: other.path,
								   putativeDescendant: self.path)
		}

		var (otherRP, selfRP) = switch try other.impl_impl_isAncestor(of: self) {
			// The order ⬇️ has to match the order of the function call ⬆️
			case .noRealpath: try Self.rp(other, self)
			case .yesRealpath(let o, let s): (o, s)
			case .none: throw nndError
		}

		guard selfRP.removePrefix(otherRP) else {
			throw nndError
		}
		return selfRP
	}
}

extension Node {
	private static func rp(_ lhs: some Node, _ rhs: some Node) throws -> (lhs: FilePath, rhs: FilePath) {
		try (lhs.realpath(), rhs.realpath())
	}

	// This indirection is so we can avoid exposing `isAncestor` on `File`
	func impl_isAncestor(of other: some Node) throws -> Bool {
		try self.impl_impl_isAncestor(of: other) != nil
	}

	// And _this_ indirection is so we can avoid calling `realpath` sometimes
	/// - Returns: `nil` if `self` is not an ancestor of `other`. Non-`nil` otherwise
	private func impl_impl_isAncestor(of other: some Node) throws -> IsAncestorProducts? {
		if other.path.starts(with: self.path) { return .noRealpath }

		let (selfRP, otherRP) = try Self.rp(self, other)
		if otherRP.starts(with: selfRP) {
			return .yesRealpath(selfRP: selfRP, otherRP: otherRP)
		} else {
			return nil
		}
	}
}

fileprivate enum IsAncestorProducts {
	case noRealpath
	case yesRealpath(selfRP: FilePath, otherRP: FilePath)
}

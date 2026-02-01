public enum NodeType: Sendable, CaseIterable {
	case dir, file, symlink, special
	#if canImport(Darwin)
		case finderAlias
	#endif

	public static var allCreatableCases: Array<Self> {
		self.allCases.filter { $0 != .special }
	}

	public var isResolvable: Bool {
		switch self {
			#if canImport(Darwin)
				case .finderAlias: fallthrough
			#endif
			case .symlink: return true
			default: return false
		}
	}

	private var nonResolvableNodeType: Optional<NonResolvableNodeType> {
		switch self {
			case .dir: .dir
			case .file: .file
			case .special: .special
			default: nil
		}
	}

	private var resolvableNodeType: Optional<ResolvableNodeType> {
		switch self {
			#if canImport(Darwin)
				case .finderAlias: .finderAlias
			#endif
			case .symlink: .symlink
			default: nil
		}
	}

	public func createNode(at pathIFP: some IntoFilePath, in fs: any FilesystemInterface) throws -> (node: any Node, target: Optional<any Node>) {
		if let nonResolvableType = self.nonResolvableNodeType {
			(try nonResolvableType.createNonResolvableNode(at: pathIFP, in: fs), nil)
		} else if let resolvableType = self.resolvableNodeType {
			try resolvableType.createTargetAndResolvableNode(at: pathIFP, in: fs)
		} else {
			throw CantBeCreated(nodeType: self)
		}
	}
}

public enum NonResolvableNodeType: Sendable, CaseIterable {
	case dir, file, special

	public static var allCreatableCases: Array<Self> {
		self.allCases.filter { $0 != .special }
	}

	public func createNonResolvableNode(at pathIFP: some IntoFilePath, in fs: any FilesystemInterface) throws -> any Node {
		switch self {
			case .dir: try fs.createDir(at: pathIFP)
			case .file: try fs.createFile(at: pathIFP)
			case .special: throw CantBeCreated(nodeType: .special)
		}
	}
}

public enum ResolvableNodeType: Sendable, CaseIterable {
	case symlink
	#if canImport(Darwin)
		case finderAlias
	#endif

	public func createResolvableNode(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath, in fs: any FilesystemInterface) throws -> any ResolvableNode {
		switch self {
			case .symlink: try fs.createSymlink(at: linkIFP, to: destIFP)
			#if canImport(Darwin)
				case .finderAlias: try fs.createFinderAlias(at: linkIFP, to: destIFP)
			#endif
		}
	}

	public func createTargetAndResolvableNode(at linkIFP: some IntoFilePath, in fs: any FilesystemInterface) throws -> (node: any Node, target: any Node) {
		let linkFP = linkIFP.into()

		let linkParent = linkFP.removingLastComponent()
		let parentDir = try fs.dir(at: linkParent)
		let target = try parentDir.newOrExistingFile(at: "target")

		let resolvable = try self.createResolvableNode(at: linkFP, to: target, in: fs)
		return (resolvable, target)
	}
}

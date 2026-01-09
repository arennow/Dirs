/// Nodes that can be resolved to another node (for example symlinks and Finder aliases).
public protocol ResolvableNode: Node {
	static var resolvableKind: ResolvableKind { get }
	func resolve() throws -> any Node
}

public extension ResolvableNode {
	var resolvableKind: ResolvableKind { Self.resolvableKind }
}

public enum ResolvableKind: Sendable, CaseIterable {
	case symlink
	#if canImport(Darwin)
		case finderAlias
	#endif

	public func createResolvableNode(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath, in fs: any FilesystemInterface) throws -> any ResolvableNode {
		let linkFP = linkIFP.into()
		let destFP = destIFP.into()

		switch self {
			case .symlink:
				return try fs.createSymlink(at: linkFP, to: destFP)
			#if canImport(Darwin)
				case .finderAlias:
					return try fs.createFinderAlias(at: linkFP, to: destFP)
			#endif
		}
	}
}

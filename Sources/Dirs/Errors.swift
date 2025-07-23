import SystemPackage

public struct NoSuchNode: Error {
	public let path: FilePath

	package init(path ifp: some IntoFilePath) {
		self.path = ifp.into()
	}
}

public struct NodeNotDescendantError: Error {
	public let putativeAncestor: FilePath
	public let putativeDescendant: FilePath

	init(putativeAncestor: FilePath, putativeDescendant: FilePath) {
		self.putativeAncestor = putativeAncestor
		self.putativeDescendant = putativeDescendant
	}
}

public struct WrongNodeType: Error, Equatable {
	public let path: FilePath
	public let actualType: NodeType

	package init(path ifp: some IntoFilePath, actualType: NodeType) {
		self.path = ifp.into()
		self.actualType = actualType
	}
}

public struct NodeAlreadyExists: Error {
	public let path: FilePath
	public let type: NodeType

	package init(path ifp: some IntoFilePath, type: NodeType) {
		self.path = ifp.into()
		self.type = type
	}
}

public struct DirLookupFailed: Error {
	public let dirLookupKind: DirLookupKind

	init(kind: DirLookupKind) {
		self.dirLookupKind = kind
	}
}

public enum InvalidPathForCall: Error, Equatable {
	case needAbsoluteWithComponent
	case needSingleComponent
	case couldNotCanonicalize(String)
}

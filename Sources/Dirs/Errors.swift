import SystemPackage

public struct NoSuchNode: Error {
	public let path: FilePath

	public init(path ifp: some IntoFilePath) {
		self.path = ifp.into()
	}
}

public struct WrongNodeType: Error, Equatable {
	public let path: FilePath
	public let actualType: NodeType

	public init(path ifp: some IntoFilePath, actualType: NodeType) {
		self.path = ifp.into()
		self.actualType = actualType
	}
}

public struct NodeAlreadyExists: Error {
	public let path: FilePath
	public let type: NodeType

	public init(path ifp: some IntoFilePath, type: NodeType) {
		self.path = ifp.into()
		self.type = type
	}
}

public enum InvalidPathForCall: Error {
	case needAbsoluteWithComponent
	case couldNotCanonicalize(String)
}

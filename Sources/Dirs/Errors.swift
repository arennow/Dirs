import SystemPackage

public struct NoSuchNode: Error {
	public let path: FilePath

	public init(path ifp: some IntoFilePath) {
		self.path = ifp.into()
	}
}

public struct WrongNodeType: Error {
	public let path: FilePath
	public let actualType: NodeType

	public init(path ifp: some IntoFilePath, actualType: NodeType) {
		self.path = ifp.into()
		self.actualType = actualType
	}
}

import Foundation
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

public struct XAttrNotSupported: Error {
	public let path: FilePath

	package init(path: FilePath) {
		self.path = path
	}
}

public struct XAttrNameTooLong: Error {
	public let attributeName: String
	public let path: FilePath

	package init(attributeName: String, path: FilePath) {
		self.attributeName = attributeName
		self.path = path
	}
}

public struct XAttrValueTooLarge: Error {
	public let attributeName: String
	public let path: FilePath

	package init(attributeName: String, path: FilePath) {
		self.attributeName = attributeName
		self.path = path
	}
}

public struct XAttrBufferTooSmall: Error {
	public let attributeName: String
	public let path: FilePath

	package init(attributeName: String, path: FilePath) {
		self.attributeName = attributeName
		self.path = path
	}
}

public struct XAttrNoSpace: Error {
	public let attributeName: String
	public let path: FilePath

	package init(attributeName: String, path: FilePath) {
		self.attributeName = attributeName
		self.path = path
	}
}

public struct XAttrInvalidUTF8: Error {
	public let attributeName: String
	public let path: FilePath
	public let data: Data

	package init(attributeName: String, path: FilePath, data: Data) {
		self.attributeName = attributeName
		self.path = path
		self.data = data
	}
}

struct XAttrNotFound: Error {}

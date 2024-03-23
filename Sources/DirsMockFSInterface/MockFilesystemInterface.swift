import Dirs
import Foundation

public struct MockFilesystemInterface: FilesystemInterface {
	public enum PartialNode {
		case file(name: String, content: String?)
		case dir(name: String, children: Array<PartialNode>)

		var isDir: Bool {
			if case .dir = self {
				return true
			}
			return false
		}

		var name: String {
			switch self {
				case .file(let name, _), .dir(let name, _):
					name
			}
		}
	}

	public let rootPartialNode: PartialNode

	private init(rootPartialNode: PartialNode) {
		self.rootPartialNode = rootPartialNode
	}

	public static func empty() -> Self {
		self.init(rootPartialNode: .dir(name: "/", children: []))
	}

	private func partialNode(at ifp: some IntoFilePath) -> PartialNode? {
		let fp = ifp.into()

		guard fp != "/" else { return self.rootPartialNode }

		var currentPartialNode = self.rootPartialNode

		for positionalElement in fp.positionalComponents {
			switch currentPartialNode {
				case .file:
					// If there's a next and the current is a file,
					// we can't resolve this path
					return nil

				case .dir(_, let children):
					guard let nextPartialNode = children.first(where: { $0.name == positionalElement.element.string }) else { return nil }

					if positionalElement.position.contains(.last) {
						return nextPartialNode
					} else {
						currentPartialNode = nextPartialNode
					}
			}
		}

		return nil
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		switch self.partialNode(at: ifp) {
			case .dir: .dir
			case .file: .file
			case .none: nil
		}
	}

	public func contentsOf(file ifp: some Dirs.IntoFilePath) throws -> Data {
		switch self.partialNode(at: ifp) {
			case .none: throw NoSuchNode(path: ifp)
			case .dir: throw WrongNodeType(path: ifp, actualType: .dir)
			case .file(_, let content): content.map { Data($0.utf8) } ?? Data()
		}
	}

	public func contentsOf(directory ifp: some Dirs.IntoFilePath) throws -> Array<FilePathStat> {
		switch self.partialNode(at: ifp) {
			case .none: throw NoSuchNode(path: ifp)
			case .file: throw WrongNodeType(path: ifp, actualType: .file)
			case .dir(_, let children):
				children.map { pnChild in
					FilePathStat(filePath: ifp.into().appending(pnChild.name), isDirectory: pnChild.isDir)
				}
		}
	}
}

public extension MockFilesystemInterface {
	init(@MockFilesystemBuilder builder: () -> PartialNode) {
		self.rootPartialNode = builder()
	}
}

public extension MockFilesystemInterface {
	@resultBuilder
	struct MockFilesystemBuilder {
		public static func buildExpression(_ expression: String) -> PartialNode {
			.file(name: expression, content: nil)
		}

		public static func buildExpression(_ expression: (String, content: String)) -> PartialNode {
			.file(name: expression.0, content: expression.content)
		}

		public static func buildExpression(_ expression: PartialNode) -> PartialNode {
			expression
		}

		public static func buildBlock(_ components: PartialNode...) -> PartialNode {
			.dir(name: "/", children: components)
		}
	}
}

public func dir(_ name: String) -> MockFilesystemInterface.PartialNode {
	.dir(name: name, children: [])
}

public func dir(_ name: String, @MockFilesystemInterface.MockFilesystemBuilder _ builder: () -> MockFilesystemInterface.PartialNode) -> MockFilesystemInterface.PartialNode {
	let res = builder()
	let children = switch res {
		case .file: [res]
		case .dir(_, let children): children
	}

	return .dir(name: name, children: children)
}

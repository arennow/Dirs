import Dirs
import Foundation
import SystemPackage

public final class MockFilesystemInterface: FilesystemInterface {
	public private(set) var rootPartialNode: PartialNode

	fileprivate init(rootPartialNode: PartialNode) {
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

	public func createDir(at fp: FilePath) throws -> Dir {
		let (pnPath, remainderComponents) = self.existingPartialNodePathAndRemainder(to: fp)

		// This array should contain just one `.dir`, which is the first new directory (and all its children)
		let newDirectoryHierarchy = remainderComponents.reversed().reduce(Array<PartialNode>()) { (partialResult, component) in
			[.dir(name: component.string, children: partialResult)]
		}

		let newRoot = try PartialNode.add(children: newDirectoryHierarchy, to: pnPath)

		self.rootPartialNode = newRoot

		return try Dir(fs: self, path: fp)
	}
}

private extension MockFilesystemInterface {
	private func existingPartialNodePathAndRemainder(to ifp: IntoFilePath) -> (pnPath: Array<PartialNode>, remainderComponents: FilePath.ComponentView.SubSequence) {
		let fp = ifp.into()
		let fpComs = fp.components

		var outPNPath = [self.rootPartialNode]
		var lastExistingComponentIndex = fpComs.startIndex

		while let pn = self.partialNode(at: fp[fragment: ..<lastExistingComponentIndex]) {
			outPNPath.append(pn)
			lastExistingComponentIndex = fpComs.index(after: lastExistingComponentIndex)
		}

		return (consume outPNPath, fpComs[lastExistingComponentIndex...])
	}
}

public extension MockFilesystemInterface {
	enum PartialNode {
		struct WrongNodeType: Error {
			let actualTypeName: String
		}

		case file(name: String, content: String?)
		case dir(name: String, children: Array<PartialNode>)

		var isDir: Bool {
			if case .dir = self { true } else { false }
		}

		var name: String {
			switch self {
				case .file(let name, _), .dir(let name, _): name
			}
		}

		fileprivate static func add(children: consuming Array<PartialNode>, to rootedGraph: consuming Array<PartialNode>) throws -> PartialNode {
			try rootedGraph.reduce(children) { (childrenToAdd, currentPN) in
				switch currentPN {
					case .file: throw PartialNode.WrongNodeType(actualTypeName: "file")
					case .dir(let name, var children):
						children.append(contentsOf: childrenToAdd)
						return [.dir(name: name, children: children)]
				}
			}.first!
		}
	}
}

public extension MockFilesystemInterface {
	convenience init(@MockFilesystemBuilder builder: () -> PartialNode) {
		self.init(rootPartialNode: builder())
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

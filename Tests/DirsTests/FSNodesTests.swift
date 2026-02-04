import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func nodeIsEqual(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file1 = try fs.createFile(at: "/file1")
		let file2 = try fs.createFile(at: "/file2")
		let dir = try fs.createDir(at: "/dir")

		let file1AsNode: any Node = file1
		let file2AsNode: any Node = file2
		let dirAsNode: any Node = dir

		#expect(file1.isEqual(to: file1AsNode))
		#expect(!file1.isEqual(to: file2AsNode))
		#expect(!file1.isEqual(to: dirAsNode))
		#expect(dir.isEqual(to: dirAsNode))
	}

	@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
	func createAllNodeKinds(fsKind: FSKind, nodeType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		let (newNode, optionalTarget) = try nodeType.createNode(at: "/newNode", in: fs)
		#expect(newNode.path == "/newNode")
		#expect(newNode.nodeType == nodeType)
		if nodeType.isResolvable {
			let target = try #require(optionalTarget)
			#expect(target.path == "/target")
		}
	}

	@Test(arguments: {
		var combinations: Array<(FSTests.FSKind, NodeType, NodeType)> = []
		for fsKind in FSTests.FSKind.allCases {
			for firstType in NodeType.allCreatableCases {
				for secondType in NodeType.allCreatableCases {
					combinations.append((fsKind, firstType, secondType))
				}
			}
		}
		return combinations
	}())
	func creatingNodeOverExistingNodeFails(fsKind: FSTests.FSKind, firstType: NodeType, secondType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		let testPath: FilePath = "/test"

		_ = try firstType.createNode(at: testPath, in: fs)
		#expect(fs.nodeType(at: testPath) == firstType)

		#expect {
			_ = try secondType.createNode(at: testPath, in: fs)
		} throws: { error in
			guard let nodeExists = error as? NodeAlreadyExists else {
				Issue.record("Expected NodeAlreadyExists, got \(type(of: error)): \(error)")
				return false
			}
			return nodeExists.path == testPath && nodeExists.type == firstType
		}

		#expect(fs.nodeType(at: testPath) == firstType)
	}

	@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
	func hashBehavior(fsKind: FSKind, nodeType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		var (node, _) = try nodeType.createNode(at: "/old", in: fs)

		let node1 = try fs.node(at: "/old")
		let node2 = try fs.node(at: "/old")
		#expect(node1.isEqual(to: node2))
		#expect(node1.hashValue == node2.hashValue)

		#expect(node.hashValue == node.hashValue)

		let oldHash = node.hashValue
		try node.rename(to: "new")
		let newHash = node.hashValue
		#expect(oldHash != newHash)
	}

	@Test(arguments: FSKind.allCases)
	func deleteNode(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")
		try fs.createFile(at: "/b")
		try fs.createFile(at: "/c").replaceContents("c content")
		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/E").replaceContents("enough!")
		try fs.createDir(at: "/f")

		try fs.deleteNode(at: "/a")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/a") }

		try fs.deleteNode(at: "/d")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/d/E") }
	}

	@Test(arguments: FSKind.allCases)
	func deleteNonexistentNodeFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(throws: (any Error).self) { try fs.deleteNode(at: "/a") }
	}

	@Test(arguments: FSKind.allCases, ResolvableNodeType.allCases)
	func resolvableKindCreateAndResolve(fsKind: FSKind, rType: ResolvableNodeType) throws {
		let fs = self.fs(for: fsKind)
		try fs.createFile(at: "/target")

		let rNode = try rType.createResolvableNode(at: "/resolvable", to: "/target", in: fs)
		#expect(rNode.path == "/resolvable")
		#expect(rNode.resolvableNodeType == rType)

		let resolved = try rNode.resolve()
		#expect(resolved.path == "/target")
	}
}

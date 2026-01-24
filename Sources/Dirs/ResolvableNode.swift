/// Nodes that can be resolved to another node (for example symlinks and Finder aliases).
public protocol ResolvableNode: Node {
	static var resolvableNodeType: ResolvableNodeType { get }
	func resolve() throws -> any Node
}

public extension ResolvableNode {
	var resolvableNodeType: ResolvableNodeType { Self.resolvableNodeType }
}

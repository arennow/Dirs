public struct CollectionPosition: RawRepresentable, OptionSet {
	public let rawValue: UInt8

	public init(rawValue: UInt8) { self.rawValue = rawValue }

	public static let first = Self(rawValue: 0b0000001)
	public static let last = Self(rawValue: 0b0000010)

	public var hasFirst: Bool { self.contains(.first) }
	public var hasLast: Bool { self.contains(.last) }
}

public struct PositionalElement<Element> {
	public let position: CollectionPosition
	public let element: Element
}

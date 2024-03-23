import Foundation
import SystemPackage

public extension FilePath {
	var url: URL { URL(string: self.string)! }

	var positionalComponents: some Collection<PositionalElement<FilePath.Component>> {
		self.components.positionEnumerated()
	}
}

extension URL {
	struct NoResourceAvailable: Error {}
	struct UnexpectedResourceType: Error {
		let expected: Any.Type
		let got: Any.Type
	}

	func getBoolResourceValue(forKey key: URLResourceKey) throws -> Bool {
		var outObj: AnyObject?
		try (self as NSURL).getResourceValue(&outObj, forKey: key)

		guard let outObj else {
			throw NoResourceAvailable()
		}

		guard let number = outObj as? NSNumber else {
			throw UnexpectedResourceType(expected: NSNumber.self, got: type(of: outObj))
		}

		return number.boolValue
	}
}

public extension Collection {
	func positionEnumerated() -> some Collection<PositionalElement<Element>> {
		let lastIndex = self.index(self.endIndex, offsetBy: -1)

		func pos(for index: Index) -> CollectionPosition {
			var out: CollectionPosition = []
			if index == self.startIndex { out.insert(.first) }
			if index == lastIndex { out.insert(.last) }
			return out
		}

		return zip(self.indices, self)
			.lazy
			.map { PositionalElement(position: pos(for: $0), element: $1) }
	}
}

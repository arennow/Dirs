import Foundation
import SystemPackage

public extension FilePath {
	var url: URL { URL(fileURLWithPath: self.string) }
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

	@available(macOS, deprecated: 13)
	@available(iOS, deprecated: 16)
	@available(tvOS, deprecated: 16)
	func pathNonPercentEncoded() -> String {
		if #available(macOS 13, iOS 16, tvOS 16, *) {
			self.path(percentEncoded: false)
		} else {
			self.path
		}
	}
}

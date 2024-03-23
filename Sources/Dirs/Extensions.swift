import Foundation
import SystemPackage

extension FilePath {
	var url: URL { URL(string: self.string)! }
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

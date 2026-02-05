import Foundation
import SystemPackage

public extension FilePath {
	var url: URL { URL(fileURLWithPath: self.string) }

	/// Normalizes a path by removing . and .. components without resolving symlinks.
	/// This is done by manipulating the components directly rather than using filesystem APIs.
	static func normalizeRelativeComponents(of ifp: some IntoFilePath) -> FilePath {
		let fp = ifp.into()
		let root = fp.root

		var normalized: Array<FilePath.Component> = []
		for component in fp.components {
			if component == FilePath.Component(".") {
				continue
			} else if component == FilePath.Component("..") {
				_ = normalized.popLast()
			} else {
				normalized.append(component)
			}
		}
		return FilePath(root: root, normalized)
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

	@inline(__always)
	func pathNonPercentEncoded() -> String {
		// This function used to conditionally call `self.path(percentEncoded: false)`
		// on platforms where it was available, but:
		// 1. This function is very important, and it's kinda silly to have it behave differently
		//    on different OS versions
		// 2. It [presently] doesn't work correctly on Windows
		self.path
	}
}

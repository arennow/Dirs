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

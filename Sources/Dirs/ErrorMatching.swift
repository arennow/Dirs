import Foundation

enum ErrorMatcher {
	case cocoa(CocoaError.Code)
	case posix(POSIXError.Code)
}

extension Error {
	func matchesAny(_ matchers: ErrorMatcher...) -> Bool {
		for matcher in matchers {
			switch matcher {
				case .cocoa(let cocoaCode):
					if let cError = self as? CocoaError, cError.code == cocoaCode {
						return true
					}
				case .posix(let posixCode):
					if let pError = self as? POSIXError, pError.code == posixCode {
						return true
					}
			}
		}
		return false
	}

	func matches(outer: ErrorMatcher, underlying: ErrorMatcher) -> Bool {
		if self.matchesAny(outer) {
			if let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? any Error {
				return underlyingError.matchesAny(underlying)
			}
		}
		return false
	}

	var userInfo: [String: Any] { (self as NSError).userInfo }
}

import Foundation
import SystemPackage

extension String: IntoFilePath {
	public func into() -> FilePath {
		FilePath(self)
	}
}

extension String: IntoData {
	public func into() -> Data {
		Data(self.utf8)
	}
}

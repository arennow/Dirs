import Foundation
import SystemPackage

extension String: IntoFilePath {
	public func into() -> FilePath {
		FilePath(self)
	}
}

extension URL: IntoFilePath {
	public func into() -> FilePath {
		if #available(macOS 13.0, *) {
			self.path(percentEncoded: false).into()
		} else {
			self.path.into()
		}
	}
}

extension FilePath: IntoFilePathComponentView {
	public func into() -> ComponentView {
		self.components
	}
}

extension FilePath.Component: IntoFilePathComponentView {
	public func into() -> FilePath.ComponentView {
		.init([self])
	}
}

extension String: IntoFilePathComponentView {
	public func into() -> FilePath.ComponentView {
		FilePath(self).into()
	}
}

extension String: IntoData {
	public func into() -> Data {
		Data(self.utf8)
	}
}

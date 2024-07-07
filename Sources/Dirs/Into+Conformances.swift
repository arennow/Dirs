import SystemPackage

extension String: IntoFilePath {
	public func into() -> FilePath {
		FilePath(self)
	}
}

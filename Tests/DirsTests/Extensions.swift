extension Collection {
	func positionEnumerated() -> some Sequence<(isLast: Bool, element: Element)> {
		let lastIndex = self.index(self.endIndex,
								   offsetBy: -1,
								   limitedBy: self.startIndex)
			?? self.startIndex

		return zip(self.indices, self)
			.lazy
			.map { (lastIndex == $0, $1) }
	}
}

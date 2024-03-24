import Dirs
import SystemPackage

extension FilePath {
	subscript<R: RangeExpression>(fragment r: R) -> FilePath where ComponentView.SubSequence.Index == R.Bound {
		if r.contains(self.components.startIndex) {
			FilePath(root: self.root, self.components[r])
		} else {
			FilePath(root: nil, self.components[r])
		}
	}
}

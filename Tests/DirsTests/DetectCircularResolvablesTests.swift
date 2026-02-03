@testable import Dirs
import SystemPackage
import Testing

struct DetectCircularResolvablesTests {
	@Test
	func allowsUniquePathsAndReturnsResult() throws {
		let result = try detectCircularResolvables { recordPathVisited in
			try recordPathVisited("/a")
			try recordPathVisited("/b")
			try recordPathVisited("/c")
			return 10
		}
		#expect(result == 10)
	}

	@Test
	func detectsCircularReferenceAndReportsStartPath() {
		#expect {
			try detectCircularResolvables { recordPathVisited in
				try recordPathVisited("/start")
				try recordPathVisited("/middle1")
				try recordPathVisited("/middle2")
				try recordPathVisited("/middle1")
			}
		} throws: { error in
			guard let circularError = error as? CircularResolvableChain else {
				return false
			}
			return circularError.startPath == "/start"
		}
	}
}

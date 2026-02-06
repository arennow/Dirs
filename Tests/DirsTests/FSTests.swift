import Dirs
import Foundation
import SystemPackage
import Testing

final class FSTests {
	var pathToDelete: FilePath?

	deinit {
		guard let pathToDelete = self.pathToDelete else { return }
		try? FileManager.default.removeItem(at: pathToDelete.url)
	}

	enum FSKind: CaseIterable {
		case mock

		#if FINDER_ALIASES_ENABLED
			// All of this silliness is required because realFS will always be able to get
			// Finder Info because we're running on APFS, so we need to be able to simulate
			// its absence (as would be the case on a non-Mac filesystem)
			enum FinderInfoAvailability: CaseIterable, CustomDebugStringConvertible {
				case available, unavailable

				var debugDescription: String {
					switch self {
						case .available: return "withFinderInfo"
						case .unavailable: return "withoutFinderInfo"
					}
				}
			}

			case real(FinderInfoAvailability)

			static var allCases: [FSKind] {
				var cases: [FSKind] = [.mock]
				for availability in FinderInfoAvailability.allCases {
					cases.append(.real(availability))
				}
				return cases
			}
		#else
			case real
		#endif
	}

	func fs(for kind: FSKind) -> any FilesystemInterface {
		switch kind {
			case .mock:
				return MockFSInterface()
			case .real:
				assert(self.pathToDelete == nil, "Each RealFSInterface test requires a unique chroot")
				var fs = try! RealFSInterface(chroot: .temporaryUnique())

				#if FINDER_ALIASES_ENABLED
					if case .real(.unavailable) = kind {
						fs.forceMissingFinderInfo = true
					}
				#endif

				self.pathToDelete = fs.chroot
				return fs
		}
	}
}

import Foundation

final class Locked<T>: @unchecked Sendable {
	private let lock = NSLock()
	private var inner: T

	init(_ inner: consuming T) {
		self.inner = inner
	}

	func read<R>(in f: (borrowing T) throws -> R) rethrows -> R {
		try self.lock.withLock {
			try f(self.inner)
		}
	}

	func mutate<R>(in f: (inout T) -> R) -> R {
		self.lock.withLock {
			f(&self.inner)
		}
	}

	subscript<K, V>(key: K) -> V? where T == Dictionary<K, V> {
		get { self.read { $0[key] }}
		set { self.mutate { $0[key] = newValue }}
	}
}

extension Locked {
	struct AcquisitionHandle: ~Copyable {
		private let parent: Locked
		var resource: T {
			_read {
				yield self.parent.inner
			}
			nonmutating _modify {
				yield &self.parent.inner
			}
		}

		fileprivate init(parent: Locked) {
			self.parent = parent
		}

		consuming func release() {}

		deinit {
			self.parent.lock.unlock()
		}
	}

	func acquireIntoHandle() -> AcquisitionHandle {
		self.lock.lock()
		return AcquisitionHandle(parent: self)
	}
}

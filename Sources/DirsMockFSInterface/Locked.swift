import Foundation

final class Locked<T>: @unchecked Sendable {
	private let lock = NSLock()
	private var inner: T

	init(_ inner: consuming T) {
		self.inner = inner
	}

	func read<R>(in f: (borrowing T) -> R) -> R {
		self.lock.withLock {
			f(self.inner)
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

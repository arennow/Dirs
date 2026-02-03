import SystemPackage

/// Detects circular resolvable chains during path resolution operations.
///
/// This helper tracks visited paths during a resolution operation and throws an error
/// if a circular reference is detected. The caller receives a closure that should be
/// called with each path as it's visited during resolution.
///
/// - Parameter operation: A closure that performs path resolution. It receives a `recordPathVisited`
///   closure which should be called with each `FilePath` encountered during resolution.
/// - Returns: The result of the operation
/// - Throws: `CircularResolvableChain` if a circular reference is detected, or any error
///   thrown by `operation`
func detectCircularResolvables<R>(in operation: (_ recordPathVisited: (FilePath) throws -> Void) throws -> R) throws -> R {
	var visited = Set<FilePath>()
	var startPath: FilePath?

	let recordPathVisited: (FilePath) throws -> Void = { path in
		if startPath == nil {
			startPath = path
		}

		if !visited.insert(path).inserted {
			// Safe to force unwrap because we're here, so at least one path was visited
			throw CircularResolvableChain(startPath: startPath!)
		}
	}

	return try operation(recordPathVisited)
}

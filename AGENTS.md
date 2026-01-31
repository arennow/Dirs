## Project explanation
This project is a high-level abstraction of filesystem interactions. It features an in-memory mock filesystem interface (`MockFSInterface`), and all behavior has to work 100% the same (from a client's perspective) between the mock interface and the real interface (`RealFSInterface`). It is **a bug** if there's a difference in observable behavior between the two.

This project is cross-platform, and is explicitly tested on macOS and Ubuntu Linux. Some features only exist on some platforms or work differently on different platforms, but in all situations, the observable behavior between real and mock FS implementations must be identical.

## Editing guidelines
- Begin by adding tests that describe the desired new/changed behavior. Iterate on the tests and the `RealFSInterface` implementation until all the tests pass (with the desired behavior). Then iterate on `MockFSInterface` until it matches established and verified behavior.
- Do not under any circumstances conditionlize behavior based on whether the code is running on a real or mock interface. This is important, so I'll say it again differently: NEVER CONDITIONALIZE TEST CODE BASED ON REAL OR MOCK FILESYSTEM INTERFACE. This is ALWAYS wrong to do.
- New tests should structurally match the existing tests – specifically the `fsKind: FSKind` argument. They should be placed near other tests that cover similar topics or behaviors.
- No test should ever rely on correct behavior to avoid crashing. Tests should never crash.
	- That means, among other things, using `#require` to verify assumptions (e.g., before using literal array subscripts)
- If you introduce new warnings in the editing process, resolve them or explain to me why you can't
- Prefer to use functions on `FilesystemInterface` for instantiating the various `Node`-conforming types rather than directly intializing those types
- Try to avoid force unwraps, but if you can't conveniently or efficiently do so, add a comment above it explaining how you can prove its safety
- For any "Into" types (e.g., `IntoFilePath`), don't resolve them (`.into()`) more than once on any path through a function

## Style preferences
- Prefer to use `self.`-style references when possible
- Prefer non-sugared forms for collection types (`Array<T>` and `Dictionary<K, V>` instead of `[T]` and `[K: V]`, respectively)
- Prefer the non-sugared form `Optional<T>` over `(T)?` when `T?` isn't viable (e.g., `Optional<any Numeric>` instead of `(any Numeric)?`) and for non-`typealias`ed closure types (e.g., `Optional<() -> Void>` instead of `(() -> Void)?`)
- Prefer a "coalescing" case (e.g., `case .some(let x): throw WrongNodeType(path: fp, actualType: x)`) instead of explicit cases for nearly identical "all the other cases" situations
	- Unless a simple `default:` will work, then prefer that
- Prefer `any P` over plain `P` for protocol existential types
- Avoid writing comments that describe obvious behavior or which make reference (implicit or otherwise) to information or history only contained in the conversation history
	- Assume the reader of the code is an experience Swift developer

## Testing instructions
- After each change, make sure all tests pass with `swift test -q`
- For some changes, I'll tell you that you should also be testing on a local Ubuntu Linux machine after each change, and to do that, run `just test_linux` (which is equivalent to running `swift test -q` on the VM via ssh)
	- Only do this during sessions when I've told you to, otherwise the VM won't be available
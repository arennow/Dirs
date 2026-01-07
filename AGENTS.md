## Project explanation
This project is a high-level abstraction of filesystem interactions. It features an in-memory mock filesystem interface (`MockFSInterface`), and all behavior has to work 100% the same (from a client's perspective) between the mock interface and the real interface (`RealFSInterface`). It is **a bug** if there's a difference in observable behavior between the two.

This project is cross-platform, and is explicitly tested on macOS and Ubuntu Linux. Some features only exist on some platforms or work differently on different platforms, but in situations, the observable behavior between real and mock FS implementations must be identical.

## Editing guidelines
- Begin by adding tests that describe the desired new/changed behavior. Iterate on the tests and the `RealFSInterface` implementation until all the tests pass (with the desired behavior). Then iterate on `MockFSInterface` until it matches established and verified behavior. Do not under any circumstances conditionlize behavior based on whether the code is running on a real or mock interface.
- New tests should structurally match the existing tests – specifically the `fsKind: FSKind` argument. They should be placed near other tests that cover similar topics or behaviors.

## Testing instructions
- After each change, make sure all tests pass with `swift test -q`
- For some changes, I'll tell you that you should also be testing on a local Ubuntu Linux machine after each change, and to do that, run `just test_linux` (which is equivalent to running `swift test -q` on the VM via ssh)
	- Only do this during sessions when I've told you to, otherwise the VM won't be available
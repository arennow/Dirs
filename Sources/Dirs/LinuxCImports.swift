#if os(Linux)
	import Glibc

	// Linux xattr functions from sys/xattr.h (not exposed by Glibc module)
	// The 'l' prefix means these operate on symlinks themselves, not their targets

	@_silgen_name("llistxattr")
	func llistxattr(_ path: UnsafePointer<CChar>!, _ list: UnsafeMutablePointer<CChar>!, _ size: Int) -> Int

	@_silgen_name("lgetxattr")
	func lgetxattr(_ path: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!, _ value: UnsafeMutableRawPointer!, _ size: Int) -> Int

	@_silgen_name("lsetxattr")
	func lsetxattr(_ path: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!, _ value: UnsafeRawPointer!, _ size: Int, _ flags: CInt) -> CInt

	@_silgen_name("lremovexattr")
	func lremovexattr(_ path: UnsafePointer<CChar>!, _ name: UnsafePointer<CChar>!) -> CInt
#endif

format:
	just _impl_format

report_errors:
	just _impl_format --lint

_impl_format *ARGS:
	swiftformat {{ARGS}} .

test:
	swift test

test_linux:
	ssh parallels@10.211.55.30 /home/parallels/.local/share/swiftly/bin/swift test -q --package-path /media/psf/Home/code/swift/Dirs
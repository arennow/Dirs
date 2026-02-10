format:
	just _impl_format

report_errors:
	just _impl_format --lint

_impl_format *ARGS:
	swiftformat {{ARGS}} .

test:
	swift test -q

test_linux:
	ssh parallels@10.211.55.30 /home/parallels/.local/share/swiftly/bin/swift test -q --package-path /media/psf/Home/code/swift/Dirs

test_windows:
	ssh -T winvm 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Users\aaron\Downloads\copy_dirs_repo_and_test.ps1"'

build_ios:
	#!/usr/bin/env bash
	set -o pipefail
	xcodebuild build -scheme Dirs -destination 'generic/platform=iOS' | xcbeautify --quiet

test_ios:
	#!/usr/bin/env bash
	SIM_ID="$(
	xcrun simctl list devices available -j \
	| jq -r '
		.devices
		| to_entries
		| map(select(.key | startswith("com.apple.CoreSimulator.SimRuntime.iOS-")))
		| sort_by(.key)
		| reverse
		| .[]
		| .value[]
		| select(((.name // "") | startswith("iPhone")))
		| .udid
		' \
	| head -n 1
	)"

	if [[ -z "${SIM_ID}" ]]; then
	print -u2 "No available iPhone simulator found."
	exit 1
	fi

	set -o pipefail
	xcodebuild test \
	-scheme Dirs \
	-destination "platform=iOS Simulator,id=${SIM_ID}" \
	| xcbeautify --quieter
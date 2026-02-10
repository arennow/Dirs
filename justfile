format:
	just _impl_format

report_errors:
	just _impl_format --lint

_impl_format *ARGS:
	swiftformat {{ARGS}} .

alias test := test_mac

test_mac:
	swift test -q

test_linux:
	ssh parallels@10.211.55.30 /home/parallels/.local/share/swiftly/bin/swift test -q --package-path /media/psf/Home/code/swift/Dirs

test_windows:
	ssh -T winvm 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Users\aaron\Downloads\copy_dirs_repo_and_test.ps1"'

build_darwin PLATFORM:
	#!/usr/bin/env bash
	set -o pipefail
	xcodebuild build -scheme Dirs -destination "generic/platform={{PLATFORM}}" | xcbeautify --quiet

test_darwin PLATFORM:
	#!/usr/bin/env bash
	set -o pipefail
	
	platform="{{PLATFORM}}"
	
	# Map platform to runtime prefix and device name prefix for simulator lookup
	case "${platform}" in
		iOS)
			runtime_prefix="com.apple.CoreSimulator.SimRuntime.iOS-"
			device_prefix="iPhone"
			;;
		tvOS)
			runtime_prefix="com.apple.CoreSimulator.SimRuntime.tvOS-"
			device_prefix="Apple TV"
			;;
		watchOS)
			runtime_prefix="com.apple.CoreSimulator.SimRuntime.watchOS-"
			device_prefix="Apple Watch"
			;;
		visionOS)
			runtime_prefix="com.apple.CoreSimulator.SimRuntime.xrOS-"
			device_prefix="Apple Vision"
			;;
		*)
			echo "Unsupported platform: ${platform}" >&2
			echo "Supported platforms: iOS, tvOS, watchOS, visionOS" >&2
			exit 1
			;;
	esac
	
	SIM_ID="$(
		xcrun simctl list devices available -j \
		| jq -r --arg runtime "${runtime_prefix}" --arg device "${device_prefix}" '
			.devices
			| to_entries
			| map(select(.key | startswith($runtime)))
			| sort_by(.key)
			| reverse
			| .[]
			| .value[]
			| select(((.name // "") | startswith($device)))
			| .udid
		' \
		| head -n 1
	)"
	
	if [[ -z "${SIM_ID}" ]]; then
		echo "No available ${device_prefix} simulator found for ${platform}." >&2
		exit 1
	fi
	
	xcodebuild test \
		-scheme Dirs \
		-destination "platform=${platform} Simulator,id=${SIM_ID}" \
		| xcbeautify --quieter

build_all_darwin:
	just build_darwin iOS
	just build_darwin tvOS
	just build_darwin watchOS
	just build_darwin visionOS

test_all_darwin:
	just test_darwin iOS
	just test_darwin tvOS
	just test_darwin watchOS
	just test_darwin visionOS

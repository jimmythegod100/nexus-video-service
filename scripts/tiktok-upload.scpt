-- TikTok Creator Center upload automation (AppleScript source)
-- Compile on macOS: osacompile -o tiktok-upload.scpt tiktok-upload.applescript
-- Invoke: osascript tiktok-upload.scpt "/absolute/path/to/video.mp4"

on run argv
	set mediaPath to item 1 of argv
	set uploadURL to "https://www.tiktok.com/creator-center/upload?from=upload"

	tell application "Google Chrome"
		if (count of windows) = 0 then make new window
		set URL of active tab of front window to uploadURL
		activate
	end tell

	delay 3

	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
		end tell
	end tell

	-- Delegate file selection to shell helper (cliclick + Go to folder)
	do shell script "bash " & quoted form of (POSIX path of ((path to home folder as text) & "nexus/scripts/lib/chrome-tiktok-select-file.sh")) & " " & quoted form of mediaPath

	return "TikTok upload initiated for " & mediaPath
end run

#!/bin/bash
# Simulator tap helper
# Usage: ./sim_tap.sh <x_pct> <y_pct> [screenshot_name]
# Taps at percentage coordinates within the Simulator device screen
# Then takes a screenshot

set -e

X_PCT=${1:?Usage: sim_tap.sh <x_pct> <y_pct> [screenshot_name]}
Y_PCT=${2:?Usage: sim_tap.sh <x_pct> <y_pct> [screenshot_name]}
SCREENSHOT_NAME=${3:-sim_screenshot}

# Get Simulator window position and size
WINDOW_INFO=$(osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1' 2>/dev/null)
WIN_X=$(echo "$WINDOW_INFO" | cut -d',' -f1 | tr -d ' ')
WIN_Y=$(echo "$WINDOW_INFO" | cut -d',' -f2 | tr -d ' ')
WIN_W=$(echo "$WINDOW_INFO" | cut -d',' -f3 | tr -d ' ')
WIN_H=$(echo "$WINDOW_INFO" | cut -d',' -f4 | tr -d ' ')

# Estimate device screen area (accounting for title bar ~28px, status bar area)
TITLE_BAR=28
DEVICE_X=$WIN_X
DEVICE_Y=$((WIN_Y + TITLE_BAR))
DEVICE_W=$WIN_W
DEVICE_H=$((WIN_H - TITLE_BAR))

# Calculate tap position
TAP_X=$(echo "$DEVICE_X + $DEVICE_W * $X_PCT / 100" | bc)
TAP_Y=$(echo "$DEVICE_Y + $DEVICE_H * $Y_PCT / 100" | bc)

echo "Window: ($WIN_X, $WIN_Y) ${WIN_W}x${WIN_H}"
echo "Tapping at ($TAP_X, $TAP_Y) [${X_PCT}%, ${Y_PCT}%]"

# Activate Simulator, tap, screenshot
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
sleep 0.3
cliclick c:${TAP_X},${TAP_Y}
sleep 0.8
xcrun simctl io booted screenshot "/tmp/${SCREENSHOT_NAME}.png"
echo "Screenshot saved to /tmp/${SCREENSHOT_NAME}.png"

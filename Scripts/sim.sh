#!/bin/bash
# iOS Simulator automation helper using Facebook IDB
# Usage:
#   ./sim.sh tap <x> <y>           - Tap at point coordinates
#   ./sim.sh screenshot [name]     - Take screenshot
#   ./sim.sh describe              - Get accessibility tree
#   ./sim.sh button <label>        - Tap button by accessibility label
#   ./sim.sh swipe <x1> <y1> <x2> <y2> - Swipe gesture
#   ./sim.sh text <string>         - Type text

set -e

UDID=$(xcrun simctl list devices booted -j | python3 -c "import json,sys; d=json.load(sys.stdin); print([u for r in d['devices'].values() for u in r if u['state']=='Booted'][0]['udid'])" 2>/dev/null)

if [ -z "$UDID" ]; then
    echo "No booted simulator found"
    exit 1
fi

case "$1" in
    tap)
        idb ui tap "$2" "$3" --udid "$UDID"
        ;;
    screenshot)
        NAME=${2:-sim_screenshot}
        xcrun simctl io booted screenshot "/tmp/${NAME}.png"
        echo "/tmp/${NAME}.png"
        ;;
    describe)
        idb ui describe-all --udid "$UDID"
        ;;
    button)
        # Find button by label and tap its center
        LABEL="$2"
        COORDS=$(idb ui describe-all --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
elements = json.load(sys.stdin)
for el in elements:
    if el.get('AXLabel') and '$LABEL' in el['AXLabel']:
        f = el['frame']
        cx = f['x'] + f['width']/2
        cy = f['y'] + f['height']/2
        print(f'{cx:.0f} {cy:.0f}')
        break
else:
    print('NOT_FOUND', file=sys.stderr)
    sys.exit(1)
")
        if [ $? -eq 0 ]; then
            X=$(echo "$COORDS" | cut -d' ' -f1)
            Y=$(echo "$COORDS" | cut -d' ' -f2)
            echo "Tapping '$LABEL' at ($X, $Y)"
            idb ui tap "$X" "$Y" --udid "$UDID"
        else
            echo "Button '$LABEL' not found"
            exit 1
        fi
        ;;
    swipe)
        idb ui swipe "$2" "$3" "$4" "$5" --udid "$UDID"
        ;;
    text)
        idb ui text "$2" --udid "$UDID"
        ;;
    square)
        # Tap a chess square by name (e.g., "d4")
        # Board layout from accessibility: rank 8 label at y=127, rank 1 at y=498
        # File labels: a at x=57, h at x=428
        # Board area: x from ~33 to ~440, y from ~120 to ~528
        # Each square: ~50.8pt wide, ~51pt tall
        FILE_CHAR="${2:0:1}"
        RANK_CHAR="${2:1:1}"

        # File index (a=0, b=1, ..., h=7)
        FILE_IDX=$(python3 -c "print(ord('$FILE_CHAR') - ord('a'))")
        RANK_IDX=$((RANK_CHAR - 1))  # rank 1=0, rank 8=7

        # Board bounds (from accessibility labels)
        BOARD_LEFT=33
        BOARD_RIGHT=440
        BOARD_TOP=120    # rank 8
        BOARD_BOTTOM=528 # rank 1

        SQ_W=$(( (BOARD_RIGHT - BOARD_LEFT) / 8 ))
        SQ_H=$(( (BOARD_BOTTOM - BOARD_TOP) / 8 ))

        # x = left + (file + 0.5) * square_width
        # y = bottom - (rank + 0.5) * square_height  (rank 1 at bottom)
        X=$(python3 -c "print(int($BOARD_LEFT + ($FILE_IDX + 0.5) * $SQ_W))")
        Y=$(python3 -c "print(int($BOARD_BOTTOM - ($RANK_IDX + 0.5) * $SQ_H))")

        echo "Tapping square $2 at ($X, $Y)"
        idb ui tap "$X" "$Y" --udid "$UDID"
        ;;
    *)
        echo "Usage: sim.sh {tap|screenshot|describe|button|swipe|text|square} [args...]"
        exit 1
        ;;
esac

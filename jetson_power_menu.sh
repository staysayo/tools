#!/usr/bin/env bash
#
# jetson_power_modes.sh
#
# A single script to manage Jetson power modes:
#   - Reads /etc/nvpmodel.conf for <POWER_MODEL> IDs/names
#   - Shows current mode (no sudo needed to query)
#   - Lets user change modes (sudo needed)
#   - Exits on ESC
#   - If 'dialog' is installed, uses TUI; otherwise single-char text-based interface.
#
# NOTE: The text-based approach expects single-digit IDs only.

###############################################################################
# 1) Basic Setup
###############################################################################

NVP_CONF="/etc/nvpmodel.conf"

if [[ ! -f "$NVP_CONF" ]]; then
  echo "Error: $NVP_CONF not found!"
  exit 1
fi

USE_DIALOG=1
if ! command -v dialog &>/dev/null; then
  USE_DIALOG=0
fi

###############################################################################
# 2) Parse Available Modes
###############################################################################

declare -A MODES  # e.g. MODES["0"]="15W"

while IFS= read -r line; do
  # Example line: < POWER_MODEL ID=0 NAME=15W >
  if [[ "$line" =~ ^\<[[:space:]]*POWER_MODEL[[:space:]]+ID=([0-9]+)[[:space:]]+NAME=(.*)\> ]]; then
    ID="${BASH_REMATCH[1]}"
    NAME="${BASH_REMATCH[2]}"
    # Remove trailing '>' and any quotes
    NAME="${NAME%>}"
    NAME="${NAME//\"/}"
    # Trim spaces
    NAME="$(echo "$NAME" | xargs)"
    MODES["$ID"]="$NAME"
  fi
done < "$NVP_CONF"

if [[ ${#MODES[@]} -eq 0 ]]; then
  echo "No <POWER_MODEL> entries found in $NVP_CONF."
  exit 1
fi

###############################################################################
# 3) get_current_mode (no sudo)
###############################################################################

get_current_mode() {
  local cid
  cid="$(nvpmodel -q --verbose 2>/dev/null \
        | grep -A1 "Current mode: NV Power Mode" \
        | tail -n1 \
        | xargs)"
  [[ -z "$cid" ]] && cid="???"
  echo "$cid"
}

###############################################################################
# 4) Sudo mode-setting
###############################################################################

change_mode() {
  local id="$1"
  local name="$2"
  local out
  out="$(sudo nvpmodel -m "$id" 2>&1)"
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "Successfully changed power mode to: $id (\"$name\")"
  else
    echo "Failed to change power mode to: $id (\"$name\")"
    echo "Error output:"
    echo "$out"
  fi
}

###############################################################################
# 5) If we have dialog, run TUI. Otherwise, single-char text approach.
###############################################################################

if [[ "$USE_DIALOG" -eq 1 ]]; then
  #-------------------------#
  # 5A) dialog-based TUI
  #-------------------------#
  while true; do
    CURRENT_ID="$(get_current_mode)"
    # Build menu: each ID => item, plus "Exit on ESC"
    menu_items=()
    for id in "${!MODES[@]}"; do
      menu_items+=( "$id" "${MODES[$id]}" )
    done

    CHOICE=$(dialog --clear \
                    --title "Jetson Power Mode Selector" \
                    --cancel-label "ESC" \
                    --default-item "$CURRENT_ID" \
                    --menu "Use ↑↓ to choose a mode. Press ESC to exit.\n\nCurrent mode: $CURRENT_ID (\"${MODES[$CURRENT_ID]}\")" \
                    20 50 12 \
                    "${menu_items[@]}" \
             2>&1 >/dev/tty)
    STATUS=$?
    clear

    # If user pressed ESC/Cancel, status != 0 => exit
    if [[ $STATUS -ne 0 ]]; then
      echo "Exiting. Goodbye!"
      exit 0
    fi

    # If user selected a mode ID
    if [[ -n "${MODES[$CHOICE]}" ]]; then
      change_mode "$CHOICE" "${MODES[$CHOICE]}"
      echo -e "\nPress <Enter> to continue..."
      read -r
    fi
  done

else
  #---------------------------------------------#
  # 5B) TEXT-based single-char approach
  #---------------------------------------------#
  echo "Warning: 'dialog' not found. Using text-based menu."
  echo "Press <Enter> to continue..."
  read -r

  while true; do
    CURRENT_ID="$(get_current_mode)"
    clear
    echo "=============================================="
    echo " Jetson Power Mode Selector (Text-Only)       "
    echo "----------------------------------------------"
    echo " Current Mode: $CURRENT_ID (\"${MODES[$CURRENT_ID]}\")"
    echo "----------------------------------------------"
    echo "Press ESC to exit or type a single digit for these modes:"
    for id in "${!MODES[@]}"; do
      echo "  $id) ${MODES[$id]}"
    done
    echo "----------------------------------------------"
    echo -n "Your selection: "

    # Read exactly one character; -s => silent, -r => raw, -n1 => 1 char
    IFS= read -rsn1 CH

    # If user pressed ESC, $CH = $'\e'
    if [[ "$CH" == $'\e' ]]; then
      echo
      echo "Exiting. Goodbye!"
      exit 0
    fi

    echo "$CH"  # echo the typed char for visual
    # If $CH is a valid single-digit ID:
    if [[ -n "${MODES[$CH]}" ]]; then
      change_mode "$CH" "${MODES[$CH]}"
    else
      echo "Invalid choice: \"$CH\""
    fi

    echo -e "\nPress <Enter> to continue..."
    read -r
  done
fi

exit 0

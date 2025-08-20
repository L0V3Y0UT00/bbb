#!/bin/bash

# Advanced Video Downloader v2.6

# ========== Dependencies Check ==========
if ! command -v dialog &> /dev/null; then
    echo "This script requires 'dialog'. Please install it (e.g., 'sudo apt install dialog' on Debian/Ubuntu)."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "This script requires 'jq'. Please install it (e.g., 'sudo apt install jq' on Debian/Ubuntu)."
    exit 1
fi
if ! [ -f /home/f43939714/.local/bin/yt-dlp ]; then
    echo "Installing yt-dlp..."
    pip install -U --user yt-dlp
    if [[ $? -ne 0 ]]; then
        echo "Failed to install yt-dlp. Please install it manually."
        exit 1
    fi
fi

# ========== Configuration ==========
STORAGE_DIR="$HOME/Videos"
CONFIG_DIR="$HOME/.config/video_downloader"
CONFIG_FILE="$CONFIG_DIR/settings.conf"
TMP_DIR="/tmp/video_downloader"
mkdir -p "$STORAGE_DIR" "$CONFIG_DIR" "$TMP_DIR"

# ========== Styling ==========
BOLD=$(tput bold)
NC=$(tput sgr0)

# ========== Functions ==========
draw_top_border() {
    printf '┌'; printf '─%.0s' $(seq 1 78); printf '┐\n'
}
draw_line() {
    printf '│%-78s│\n' "$1"
}
draw_bottom_border() {
    printf '└'; printf '─%.0s' $(seq 1 78); printf '┘\n'
}
center_text() {
    text="$1"
    text_length=${#text}
    padding=$(( (78 - text_length) / 2 ))
    printf "%${padding}s%s%${padding}s" "" "$text" ""
}
get_mem_usage() {
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used=$((mem_total - mem_free))
        mem_percent=$((mem_used * 100 / mem_total))
        echo "Mem: ${mem_percent}%"
    else
        echo "Mem: N/A"
    fi
}

# ========== Header ==========
clear
draw_top_border
draw_line "$(center_text "${BOLD}Advanced Video Downloader v2.6${NC}")"
draw_bottom_border
echo

# ========== Settings Setup ==========
if [ ! -f "$CONFIG_FILE" ]; then
    dialog --title "First-Time Setup" --msgbox "Welcome! Please select the platforms you want to enable." 8 60
    enabled_platforms=$(dialog --stdout --title "Platform Selection" --checklist "Select platforms to enable:" 15 60 7 \
        "YouTube" "Download videos from YouTube" on \
        "TikTok" "Download videos from TikTok" off \
        "Instagram" "Download videos from Instagram" off \
        "Facebook" "Download videos from Facebook" off \
        "Twitter" "Download videos from Twitter/X" off \
        "Vimeo" "Download videos from Vimeo" off \
        "Dailymotion" "Download videos from Dailymotion" off)
    if [ -z "$enabled_platforms" ]; then
        dialog --title "Error" --msgbox "No platforms selected. Please select at least one platform." 8 60
        exit 1
    fi
    echo "$enabled_platforms" > "$CONFIG_FILE"
fi

# ========== Edit Settings Function ==========
edit_settings() {
    current_settings=$(cat "$CONFIG_FILE")
    enabled_platforms=$(dialog --stdout --title "Edit Platform Settings" --checklist "Select platforms to enable:" 15 60 7 \
        "YouTube" "Download videos from YouTube" $([[ "$current_settings" =~ "YouTube" ]] && echo "on" || echo "off") \
        "TikTok" "Download videos from TikTok" $([[ "$current_settings" =~ "TikTok" ]] && echo "on" || echo "off") \
        "Instagram" "Download videos from Instagram" $([[ "$current_settings" =~ "Instagram" ]] && echo "on" || echo "off") \
        "Facebook" "Download videos from Facebook" $([[ "$current_settings" =~ "Facebook" ]] && echo "on" || echo "off") \
        "Twitter" "Download videos from Twitter/X" $([[ "$current_settings" =~ "Twitter" ]] && echo "on" || echo "off") \
        "Vimeo" "Download videos from Vimeo" $([[ "$current_settings" =~ "Vimeo" ]] && echo "on" || echo "off") \
        "Dailymotion" "Download videos from Dailymotion" $([[ "$current_settings" =~ "Dailymotion" ]] && echo "on" || echo "off"))
    if [ -z "$enabled_platforms" ]; then
        dialog --title "Error" --msgbox "No platforms selected. Keeping existing settings." 8 60
    else
        echo "$enabled_platforms" > "$CONFIG_FILE"
        dialog --title "Success" --msgbox "Settings updated successfully." 8 60
    fi
}

# ========== Main Loop ==========
while true; do
    choice=$(dialog --stdout --title "Video Downloader" --menu "Choose an option:" 10 60 2 \
        1 "Enter URL or Username" \
        2 "Edit Settings")
    clear
    case $choice in
        1)
            user_input=$(dialog --stdout --title "Input" --inputbox "Enter a URL or Username:" 8 70)
            if [ -z "$user_input" ]; then
                dialog --title "Error" --msgbox "No input provided." 8 40
                continue
            fi
            break
            ;;
        2)
            edit_settings
            continue
            ;;
        *)
            clear
            exit 0
            ;;
    esac
done

# ========== Platform Detection ==========
platform="Unknown"
if [[ "$user_input" =~ (youtube\.com|youtu\.be) ]]; then
    platform="YouTube"
elif [[ "$user_input" =~ tiktok\.com ]]; then
    platform="TikTok"
elif [[ "$user_input" =~ instagram\.com ]]; then
    platform="Instagram"
elif [[ "$user_input" =~ (facebook\.com|fb\.com) ]]; then
    platform="Facebook"
elif [[ "$user_input" =~ (twitter\.com|x\.com) ]]; then
    platform="Twitter"
elif [[ "$user_input" =~ vimeo\.com ]]; then
    platform="Vimeo"
elif [[ "$user_input" =~ dailymotion\.com ]]; then
    platform="Dailymotion"
else
    if [[ ! "$user_input" =~ \. ]]; then
        platform="TikTok"
    fi
fi

# ========== Platform Enabled Check ==========
if [[ "$platform" != "Unknown" ]]; then
    enabled_platforms=$(cat "$CONFIG_FILE")
    is_enabled=0
    for enabled_platform in $enabled_platforms; do
        if [[ "$platform" == "$enabled_platform" ]]; then
            is_enabled=1
            break
        fi
    done
    if [[ $is_enabled -eq 0 ]]; then
        dialog --title "Platform Disabled" --msgbox "The URL is from '$platform', which is currently disabled in your settings.\n\nTo enable it, select 'Edit Settings' or delete your settings file:\n$CONFIG_FILE" 10 70
        exit 1
    fi
fi

# ========== Final URL Construction ==========
if [[ "$platform" == "TikTok" && ! "$user_input" =~ ^https?:// ]]; then
    final_url="https://www.tiktok.com/@$user_input"
else
    final_url="$user_input"
fi

if [[ "$platform" == "Unknown" ]]; then
    dialog --title "Error" --msgbox "Could not determine platform from input: $user_input" 8 60
    exit 1
fi

# ========== Extract Playlist ==========
dialog --title "Status" --infobox "Extracting videos from $platform..." 5 40
channel_json=$(/home/f43939714/.local/bin/yt-dlp --flat-playlist --dump-single-json "$final_url" 2> yt-dlp-error.log)
if [[ $? -ne 0 ]]; then
    error_msg=$(cat yt-dlp-error.log)
    dialog --title "yt-dlp Error" --msgbox "$error_msg" 20 70
    exit 1
fi
if [ -f yt-dlp-error.log ]; then
    rm -f yt-dlp-error.log
fi
echo "$channel_json" > channel_json.txt

channel_title=$(echo "$channel_json" | jq -r '.title // "unknown_channel"' | sed 's/[^a-zA-Z0-9_-]/_/g')
output_file="@${channel_title}_videos.txt"

urls=$(echo "$channel_json" | jq -r '.entries[].url // empty')
if [[ -z "$urls" ]]; then
    dialog --title "Error" --msgbox "No URLs found." 8 40
    exit 1
fi
printf "%s\n" "$urls" > "$output_file"
dialog --title "Success" --msgbox "Saved video URLs to $output_file" 8 60

# ========== File Picker ==========
items=()
i=1
for item in *.txt; do
    items+=("$i" "$item")
    i=$((i+1))
done
dialog_height=$((${#items[@]}/2 + 8))
if [ $dialog_height -gt 20 ]; then dialog_height=20; fi
choice_index=$(dialog --stdout --title "File Picker" --menu "Select a file:" $dialog_height 70 0 "${items[@]}")
clear
if [ -z "$choice_index" ]; then
    dialog --title "Error" --msgbox "No file selected." 8 40
    exit 1
fi
selected=""
for i in "${!items[@]}"; do
    if [[ "${items[i]}" == "$choice_index" ]]; then
        selected="${items[i+1]}"
        break
    fi
done
file_selected="$selected"

# ========== Range Selection ==========
total_lines=$(wc -l < "$file_selected")
range_label=$(basename "$file_selected" .txt)
range_input=$(dialog --stdout --title "Range Selection" --inputbox "Enter range (1-$total_lines) to download from $file_selected (e.g., 3-10):" 8 70)
clear
start=$(echo "$range_input" | cut -d'-' -f1)
end=$(echo "$range_input" | cut -d'-' -f2)
if ! [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$end" -ge "$start" && "$start" -le "$total_lines" ]]; then
    dialog --title "Error" --msgbox "Invalid range: $range_input" 8 40
    exit 1
fi
selected_urls=$(sed -n "${start},${end}p" "$file_selected")
mapfile -t urls_to_download < <(echo "$selected_urls")
total_videos=${#urls_to_download[@]}
download_dir="${STORAGE_DIR}/${range_label}_videos"
mkdir -p "$download_dir"

# ========== Download Loop ==========
(
    downloaded_count=0
    for url in "${urls_to_download[@]}"; do
        downloaded_count=$((downloaded_count + 1))
        percentage=$((downloaded_count * 100 / total_videos))
        mem_usage=$(get_mem_usage)
        echo $percentage
        echo "XXX"
        echo "Downloading video $downloaded_count of $total_videos... [$platform] [$mem_usage]\n$url"
        echo "XXX"
        /home/f43939714/.local/bin/yt-dlp -q -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" -o "${download_dir}/%(title).80s.%(ext)s" "$url"
    done
) | dialog --title "Downloading" --gauge "Starting download..." 10 70 0
clear
dialog --title "Success" --msgbox "Download complete!\n\nAll videos have been saved to:\n$download_dir" 10 70
clear

# Ask to continue or exit
dialog --yesno "Download process finished. Would you like to download another URL?" 8 60
response=$?
case $response in
    0) clear;; # Yes, continue loop
    1) clear; exit 0;; # No
    255) clear; exit 0;; # Escape
esac
done

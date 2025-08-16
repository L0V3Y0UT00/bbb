#!/bin/bash

# ========== Styling ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# ========== Box Drawing Functions ==========
get_width() {
    tput cols
}

draw_top_border() {
    local width=$(get_width)
    echo -e "${BLUE}╭$(printf '─%.0s' $(seq 1 $((width - 2))))╮${NC}"
}

draw_bottom_border() {
    local width=$(get_width)
    echo -e "${BLUE}╰$(printf '─%.0s' $(seq 1 $((width - 2))))╯${NC}"
}

draw_separator() {
    local width=$(get_width)
    echo -e "${BLUE}├$(printf '─%.0s' $(seq 1 $((width - 2))))┤${NC}"
}

draw_line() {
    local text="$1"
    local width=$(get_width)
    local content_width=$((width - 4))
    printf "${BLUE}│${NC} %-${content_width}s ${BLUE}│${NC}\n" "$text"
}

center_text() {
    local text="$1"
    local width=$(get_width)
    local content_width=$((width - 4))
    local text_len_no_color=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g' | wc -m)
    local pad=$(((content_width - text_len_no_color) / 2))
    printf "%*s%s%*s" $pad "" "$text" $pad ""
}

# ========== Header ==========
clear
draw_top_border
draw_line "$(center_text "${BOLD}Advanced Video Downloader v2.0${NC}")"
draw_bottom_border
echo

# ========== Environment Detection ==========
if [[ -d "/data/data/com.termux/files" ]]; then
    IS_TERMUX=1
    STORAGE_DIR="/storage/emulated/0"
    TMP_DIR="/data/data/com.termux/files/usr/tmp"
    PKG_MANAGER="pkg"
else
    IS_TERMUX=0
    STORAGE_DIR="$HOME/Downloads"
    TMP_DIR="/tmp"
    if command -v apt >/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null; then
        PKG_MANAGER="yum"
    else
        dialog --title "Error" --msgbox "No supported package manager found. Exiting." 8 40
        exit 1
    fi
fi

# ========== Termux Storage Setup ==========
if [[ $IS_TERMUX -eq 1 && ! -d "$STORAGE_DIR" ]]; then
    dialog --title "Setup" --infobox "Setting up Termux storage access..." 5 40
    termux-setup-storage
    sleep 2
fi

# ========== Dependencies ==========
get_mem_usage() {
    if [[ -f /proc/meminfo ]]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used=$((mem_total - mem_free))
        mem_percent=$((mem_used * 100 / mem_total))
        echo "Mem: ${mem_percent}%"
    else
        echo "Mem: N/A"
    fi
}

install_dependencies_with_progress() {
    local dependencies=($@)
    local total_deps=${#dependencies[@]}
    local installed_count=0

    (
    for dep in "${dependencies[@]}"; do
        pkg_name=$(echo $dep | cut -d':' -f1)
        termux_pkg_name=$(echo $dep | cut -d':' -f2)
        if ! command -v "$pkg_name" &>/dev/null; then
            if [[ $IS_TERMUX -eq 1 ]]; then
                pkg update -y >/dev/null 2>&1 && pkg install -y "${termux_pkg_name:-$pkg_name}" >/dev/null 2>&1
            else
                case $PKG_MANAGER in
                    apt) sudo apt update >/dev/null 2>&1 && sudo apt install -y "$pkg_name" >/dev/null 2>&1;; 
                    dnf|yum) sudo $PKG_MANAGER install -y "$pkg_name" >/dev/null 2>&1;; 
                esac
            fi
        fi
        installed_count=$((installed_count + 1))
        percentage=$((installed_count * 100 / total_deps))
        echo $percentage
    done

    if ! command -v yt-dlp &>/dev/null; then
        if [[ $IS_TERMUX -eq 1 ]]; then
            pkg install -y python >/dev/null 2>&1 && pip install -U yt-dlp >/dev/null 2>&1
        else
            if ! command -v pip &>/dev/null; then
                case $PKG_MANAGER in
                    apt) sudo apt update >/dev/null 2>&1 && sudo apt install -y python3-pip >/dev/null 2>&1;; 
                    dnf|yum) sudo $PKG_MANAGER install -y python3-pip >/dev/null 2>&1;; 
                esac
            fi
            pip install -U yt-dlp --user >/dev/null 2>&1
            export PATH="$HOME/.local/bin:$PATH"
        fi
    else
        pip install -U yt-dlp --user >/dev/null 2>&1
    fi
    echo 100
    ) | dialog --title "Setup" --gauge "Installing dependencies..." 10 70 0
}

dependencies=("jq:jq" "ffmpeg:ffmpeg" "dialog:dialog")
install_dependencies_with_progress "${dependencies[@]}"


# ========== URL Input ==========
if [ -n "$1" ]; then
    user_input="$1"
else
    user_input=$(dialog --stdout --title "URL Input" --inputbox "Enter YouTube/TikTok Channel URL or Username:" 8 70)
fi
clear

if [[ "$user_input" =~ ^[a-zA-Z0-9_.]+$ ]]; then
    final_url="https://www.tiktok.com/@$user_input"
    platform="TikTok"
elif [[ "$user_input" =~ ^https?://(www\.)?tiktok\.com/@[a-zA-Z0-9_.-]+$ ]]; then
    final_url="$user_input"
    platform="TikTok"
elif [[ "$user_input" =~ ^https?:// ]]; then
    final_url="$user_input"
    platform="YouTube"
else
    dialog --title "Error" --msgbox "Invalid input." 8 40
    exit 1
fi

# ========== Extract Playlist ==========
dialog --title "Status" --infobox "Extracting videos from $platform..." 5 40
channel_json=$(yt-dlp --flat-playlist --dump-single-json "$final_url" 2> yt-dlp-error.log)
if [[ $? -ne 0 ]]; then
    error_msg=$(cat yt-dlp-error.log)
    dialog --title "yt-dlp Error" --msgbox "$error_msg" 20 70
    exit 1
fi
rm -f yt-dlp-error.log
echo "$channel_json" > channel_json.txt

channel_title=$(echo "$channel_json" | jq -r '.title // "unknown_channel"' | sed 's/[^a-zA-Z0-9_-]/_/g')
output_file="@${channel_title}_shorts.txt"

urls=$(echo "$channel_json" | jq -r '.entries[]?.url // empty')
if [[ -z "$urls" ]]; then
    dialog --title "Error" --msgbox "No URLs found." 8 40
    exit 1
fi

indexed_urls=()
while IFS= read -r url; do
    if [[ "$platform" == "tiktok" ]]; then
        username=$(basename "$final_url")
        full_url="https://www.tiktok.com/$username/video/${url##*/}"
    else
        full_url="https://www.youtube.com/shorts/${url##*/}"
    fi
    indexed_urls+=("$full_url")
done <<< "$urls"

printf "%s\n" "${indexed_urls[@]}" > "$output_file"
dialog --title "Success" --msgbox "Saved ${#indexed_urls[@]} URLs to $output_file" 8 60

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

# Get the selected item from the index
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

# Get total number of videos
mapfile -t urls_to_download < <(echo "$selected_urls")
total_videos=${#urls_to_download[@]}

# Create download directory
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
    yt-dlp -q -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" -o "${download_dir}/%(title).80s.%(ext)s" "$url"
done
) | dialog --title "Downloading" --gauge "Starting download..." 10 70 0

clear
dialog --title "Success" --msgbox "Download complete!\n\nAll videos have been saved to:\n$download_dir" 10 70
clear

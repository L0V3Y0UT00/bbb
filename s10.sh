#!/bin/bash

# ========== Configuration and Setup ==========
CONFIG_DIR="$HOME/.config/video_downloader"
CONFIG_FILE="$CONFIG_DIR/settings.conf"

# Function to run the first-time setup for platform selection
perform_first_time_setup() {
    all_platforms=(
        "YouTube"
        "TikTok"
        "Facebook"
        "Instagram"
        "Twitter"
        "Twitch"
        "Vimeo"
        "Dailymotion"
        "SoundCloud"
    )
    platform_list_text="Enter the numbers of the platforms you want to enable as a single string (e.g., 12345).\n\n"
    i=1
    for p in "${all_platforms[@]}"; do
        platform_list_text+="$i. $p\n"
        i=$((i+1))
    done
    selection_string=$(dialog --stdout --title "One-Time Setup" --inputbox "$platform_list_text" 20 60)
    enabled_platforms_to_save=()
    if [[ -z "$selection_string" ]]; then
        enabled_platforms_to_save=("YouTube" "TikTok" "Facebook" "Instagram" "Twitter")
        dialog --title "Setup" --msgbox "No platforms selected. A default set has been enabled." 8 60
    else
        for (( i=0; i<${#selection_string}; i++ )); do
            digit="${selection_string:$i:1}"
            if [[ "$digit" =~ ^[1-9]$ ]]; then
                index=$((digit - 1))
                if [[ $index -lt ${#all_platforms[@]} ]]; then
                    enabled_platforms_to_save+=("${all_platforms[$index]}")
                fi
            fi
        done
        enabled_platforms_to_save=($(printf "%s\n" "${enabled_platforms_to_save[@]}" | sort -u))
    fi
    mkdir -p "$CONFIG_DIR"
    printf "%s\n" "${enabled_platforms_to_save[@]}" > "$CONFIG_FILE"
    dialog --title "Setup Complete" --msgbox "Your platform preferences have been saved." 8 60
}

# ========== Styling ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# ========== Box Drawing Functions ==========
get_width() { tput cols; }
draw_top_border() { local width=$(get_width); echo -e "${BLUE}╭$(printf '─%.0s' $(seq 1 $((width - 2))))╮${NC}"; }
draw_bottom_border() { local width=$(get_width); echo -e "${BLUE}╰$(printf '─%.0s' $(seq 1 $((width - 2))))╯${NC}"; }
draw_separator() { local width=$(get_width); echo -e "${BLUE}├$(printf '─%.0s' $(seq 1 $((width - 2))))┤${NC}"; }
draw_line() { local text="$1"; local width=$(get_width); local content_width=$((width - 4)); printf "${BLUE}│${NC} %-${content_width}s ${BLUE}│${NC}\n" "$text"; }
center_text() { local text="$1"; local width=$(get_width); local content_width=$((width - 4)); local text_len_no_color=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g' | wc -m); local pad=$(((content_width - text_len_no_color) / 2)); printf "%*s%s%*s" $pad "" "$text" $pad ""; }

# ========== Header ==========
clear
draw_top_border
draw_line "$(center_text "${BOLD}Advanced Video Downloader v2.4${NC}")"
draw_bottom_border
echo

# ========== Initial Setup Check ==========
if [ ! -f "$CONFIG_FILE" ]; then
    perform_first_time_setup
fi
mapfile -t enabled_platforms < "$CONFIG_FILE"

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
    if command -v apt >/dev/null; then PKG_MANAGER="apt"; elif command -v dnf >/dev/null; then PKG_MANAGER="dnf"; elif command -v yum >/dev/null; then PKG_MANAGER="yum"; else echo "No supported package manager found. Exiting."; exit 1; fi
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
                    apt)
                        echo "Updating package lists and installing '$pkg_name'..." > /dev/tty
                        sudo apt-get update -y > /dev/tty
                        sudo apt-get install -y "$pkg_name" > /dev/tty
                        ;;
                    dnf|yum)
                        echo "Installing '$pkg_name' with $PKG_MANAGER..."
                        sudo $PKG_MANAGER install -y "$pkg_name"
                        ;;
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

# ========== Termux Repo Fix ==========
if [[ $IS_TERMUX -eq 1 ]]; then
    if grep -q "packages.termux.org" /data/data/com.termux/files/usr/etc/apt/sources.list 2>/dev/null; then
        dialog --title "Fixing Termux" --infobox "Your Termux installation seems to be using an outdated package repository.\n\nAttempting to switch to a working repository automatically." 10 70
        sleep 3
        sed -i 's@^deb.*packages.termux.org.*$@deb https://grimler.se/termux-packages-24 stable main@' /data/data/com.termux/files/usr/etc/apt/sources.list
        
        dialog --title "Fixing Termux" --infobox "Repository has been changed. Running pkg update..." 5 70
        pkg update -y
        if [[ $? -eq 0 ]]; then
            dialog --title "Success" --msgbox "Termux package repository has been successfully updated. The script will now proceed." 8 60
        else
            dialog --title "Error" --msgbox "Failed to update package lists from the new repository. Please check your internet connection or try running 'termux-change-repo' manually." 8 60
            exit 1
        fi
    fi
fi

if [[ $IS_TERMUX -eq 1 ]]; then
    dependencies=("jq:jq" "ffmpeg:ffmpeg" "dialog:dialog" "termux-api:termux-api")
    install_dependencies_with_progress "${dependencies[@]}"
fi

# ========== URL Input ==========
if [ -n "$1" ]; then
    user_input="$1"
else
    clipboard_content=""
    if [[ $IS_TERMUX -eq 1 ]]; then
        if command -v termux-clipboard-get >/dev/null; then
            clipboard_content=$(termux-clipboard-get)
        fi
    else
        if command -v xclip >/dev/null; then
            clipboard_content=$(xclip -o -selection clipboard)
        fi
    fi

    if [[ "$clipboard_content" =~ ^https?:// ]]; then
        dialog --title "URL Detected" --infobox "Detected a URL in your clipboard. Using it automatically...\n\n$clipboard_content" 6 70
        user_input="$clipboard_content"
        sleep 2
    else
        choice=$(dialog --stdout --title "URL Input" --menu "Choose input method:" 10 40 2 1 "Enter URL manually" 2 "Paste from clipboard")
        case $choice in
            1) user_input=$(dialog --stdout --title "URL Input" --inputbox "Enter a URL or Username:" 8 70) ;; 
            2) user_input="$clipboard_content" ;; 
            *) exit 1 ;; 
        esac
    fi
fi
clear

# ========== Username or URL Handling ==========
if [[ ! "$user_input" =~ "://" && ! "$user_input" =~ "/" ]]; then
    platform_choice=$(dialog --stdout --title "Username Detected" --menu "Input '$user_input' looks like a username. What should I do?" 12 70 2 \
        1 "Assume it is a TikTok username" \
        2 "Search for it on multiple platforms")

    clear
    
    case $platform_choice in
        1) 
            user_input="https://www.tiktok.com/@$user_input"
            ;; 
        2) 
            LOG_FILE="${TMP_DIR}/username_check.log"
            > "$LOG_FILE"
            dialog --title "Searching..." --infobox "Searching for user '$user_input' across multiple platforms..." 5 70
            platforms_to_check=(
                "YouTube https://www.youtube.com/@"
                "TikTok https://www.tiktok.com/@"
                "Instagram https://www.instagram.com/"
                "Twitter https://twitter.com/"
                "Reddit https://www.reddit.com/user/"
                "Pinterest https://www.pinterest.com/"
                "Vimeo https://vimeo.com/"
            )
            found_platforms_options=()
            is_first_found="on"
            (
            checked_count=0
            total_to_check=${#platforms_to_check[@]}
            for platform_info in "${platforms_to_check[@]}"; do
                platform_name=$(echo "$platform_info" | cut -d' ' -f1)
                base_url=$(echo "$platform_info" | cut -d' ' -f2)
                url_to_check="${base_url}${user_input}"
                command_to_run="curl -s -L -o /dev/null -w \"%{http_code}\" \"$url_to_check\""
                http_code=$(eval $command_to_run)
                echo "[$platform_name] Pattern: ${base_url}<username>" >> "$LOG_FILE"
                echo "  -> Command: $command_to_run" >> "$LOG_FILE"
                echo "  -> Checking: $url_to_check" >> "$LOG_FILE"
                echo "  -> Result: HTTP $http_code" >> "$LOG_FILE"
                echo "" >> "$LOG_FILE"
                if [[ "$http_code" == "200" ]]; then
                    found_platforms_options+=("$platform_name" "$url_to_check" "$is_first_found")
                    is_first_found="off"
                fi
                checked_count=$((checked_count + 1))
                percentage=$((checked_count * 100 / total_to_check))
                echo $percentage
                echo "XXX"
                echo "Checking $platform_name (HTTP $http_code)..."
                echo "XXX"
            done
            ) | dialog --title "Searching for User" --gauge "Checking for username '$user_input'..." 10 70 0
            dialog --title "Search Log" --textbox "$LOG_FILE" 20 70
            rm "$LOG_FILE"
            if [ ${#found_platforms_options[@]} -eq 0 ]; then
                dialog --title "Not Found" --msgbox "The username '$user_input' could not be found." 8 60
                exit 1
            fi
            num_found=$((${#found_platforms_options[@]} / 3))
            chosen_url=$(dialog --stdout --title "Platform Selection" --radiolist "Username '$user_input' found on these platforms. Choose one:" 15 70 $num_found "${found_platforms_options[@]}")
            clear
            if [ -z "$chosen_url" ]; then
                echo "No platform selected. Exiting."
                exit 1
            fi
            user_input="$chosen_url"
            ;; 
        *)
            echo "No option selected. Exiting."
            exit 1
            ;; 
    esac
fi

# ========== Advanced Platform Detection ==========
platform="Unknown"
url_type="Unknown"

case "$user_input" in
    *youtube.com/shorts/*|*youtube.com/watch*|*youtu.be/*) platform="YouTube"; url_type="video" ;; 
    *youtube.com/@*|*youtube.com/channel/*|*youtube.com/c/*) platform="YouTube"; url_type="channel" ;; 
    *youtube.com/playlist*) platform="YouTube"; url_type="playlist" ;; 
    ytsearch:*) platform="YouTube"; url_type="search" ;; 
    *facebook.com/reel/*|*facebook.com/watch*|*fb.watch*) platform="Facebook"; url_type="video" ;; 
    *instagram.com/reel/*|*instagram.com/p/*) platform="Instagram"; url_type="video" ;; 
    *instagram.com/stories/*) platform="Instagram"; url_type="story" ;; 
    *instagram.com/explore/tags/*) platform="Instagram"; url_type="search" ;; 
    *instagram.com/*) platform="Instagram"; url_type="channel" ;; 
    *tiktok.com/@*/video/*|*vm.tiktok.com/*) platform="TikTok"; url_type="video" ;; 
    *tiktok.com/live/*) platform="TikTok"; url_type="live" ;; 
    *tiktok.com/@*) platform="TikTok"; url_type="channel" ;; 
    *vimeo.com/[0-9]*) platform="Vimeo"; url_type="video" ;; 
    *vimeo.com/channels/*) platform="Vimeo"; url_type="channel" ;; 
    *vimeo.com/user[0-9]*) platform="Vimeo"; url_type="channel" ;; 
    *dailymotion.com/video/*) platform="Dailymotion"; url_type="video" ;; 
    *dailymotion.com/playlist/*) platform="Dailymotion"; url_type="playlist" ;; 
    *dailymotion.com/user/*) platform="Dailymotion"; url_type="channel" ;; 
    *twitch.tv/videos/*|*twitch.tv/*/clip/*) platform="Twitch"; url_type="video" ;; 
    *twitch.tv/collections/*) platform="Twitch"; url_type="playlist" ;; 
    *twitch.tv/*) platform="Twitch"; url_type="channel" ;; 
    *twitter.com/*/status/*|*x.com/*/status/*) platform="Twitter"; url_type="video" ;; 
    *soundcloud.com/sets/*) platform="SoundCloud"; url_type="playlist" ;; 
    *soundcloud.com/*/*) platform="SoundCloud"; url_type="video" ;; 
    scsearch:*) platform="SoundCloud"; url_type="search" ;; 
    *bilibili.com/video/*) platform="Bilibili"; url_type="video" ;; 
    *bilibili.com/bangumi/play/*) platform="Bilibili"; url_type="playlist" ;; 
    *space.bilibili.com/*) platform="Bilibili"; url_type="channel" ;; 
    bilisearch:*) platform="Bilibili"; url_type="search" ;; 
esac

# ========== Platform Enabled Check ==========
if [[ "$platform" != "Unknown" ]]; then
    is_enabled=0
    for enabled_platform in "${enabled_platforms[@]}"; do
        if [[ "$platform" == "$enabled_platform" ]]; then
            is_enabled=1
            break
        fi
    done

    if [[ $is_enabled -eq 0 ]]; then
        dialog --title "Platform Disabled" --msgbox "The URL is from '$platform', which is currently disabled in your settings.\n\nTo enable it, delete your settings file to re-run the setup:\n$CONFIG_FILE" 10 70
        exit 1
    fi
fi

# ========== Download Logic ==========
final_url="$user_input"

if [[ "$platform" == "Unknown" ]]; then
    dialog --title "Error" --msgbox "Could not determine the platform from the input URL. Please use a valid video, channel, or playlist URL." 8 70
    exit 1
fi

if [[ "$url_type" == "video" || "$url_type" == "story" || "$url_type" == "live" ]]; then
    dialog --title "Direct Download" --infobox "Detected a single $url_type from $platform. Starting download..." 5 70
    download_dir="${STORAGE_DIR}/Downloaded_Videos"
    mkdir -p "$download_dir"
    (
    echo 10
    echo "XXX"
    echo "Downloading single video...\n$final_url"
    echo "XXX"
    yt-dlp -q -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" -o "${download_dir}/%(title).80s.%(ext)s" "$final_url"
    echo 100
    ) | dialog --title "Downloading" --gauge "Starting download..." 10 70 0
    clear
    dialog --title "Success" --msgbox "Download complete!\n\nVideo saved to:\n$download_dir" 10 70
    clear
    exit 0
fi

if [[ "$url_type" == "channel" || "$url_type" == "playlist" || "$url_type" == "search" ]]; then
    dialog --title "Status" --infobox "Extracting video list from $platform $url_type..." 5 60
    channel_json=$(yt-dlp --flat-playlist --dump-single-json "$final_url" 2> yt-dlp-error.log)
    if [[ $? -ne 0 ]]; then
        error_msg=$(cat yt-dlp-error.log)
        dialog --title "yt-dlp Error" --msgbox "$error_msg" 20 70
        exit 1
    fi
    if [ -f yt-dlp-error.log ]; then
        dialog --yesno "A 'yt-dlp-error.log' file was created. It appears to be empty. Do you want to delete it?" 7 60
        if [ $? -eq 0 ]; then
            rm -f yt-dlp-error.log
        fi
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
        yt-dlp -q -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" -o "${download_dir}/%(title).80s.%(ext)s" "$url"
    done
    ) | dialog --title "Downloading" --gauge "Starting download..." 10 70 0
    clear
    dialog --title "Success" --msgbox "Download complete!\n\nAll videos have been saved to:\n$download_dir" 10 70
    clear
fi

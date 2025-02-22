# Copyright Delta Networks
# Version: 1.0-22022025
# Author: Rhys

# Install to scripts, install script
# Start mod script

#!/bin/bash

if [[ "${ENABLE_MODS}" == "1" ]]; then
    echo "Daemon detects server mode is 1."
    echo "Mods enabled, running script.."

    # Config
    username="${SERVER_USERNAME}"
    token="${SERVER_TOKEN}"
    DOWNLOAD_DIR="/mnt/server/mods"

    # Input string of mod names (comma-separated)
    MOD_NAMES_STRING="${MOD_NAMES}"

    # Convert the comma-separated string into an array
    IFS=',' read -r -a mods <<< "$MOD_NAMES_STRING"

    # Function
    download_latest_mod_version() {
        mod_name=$1
        echo "Fetching latest version for $mod_name..."

        response=$(curl -s "https://mods.factorio.com/api/mods/$mod_name")

        IFS=$'\n' read -rd '' -a lines <<<"$(echo "$response" | grep -oP '"released_at":"\K[^"]+|download_url":"\K[^"]+')"

        latest_date=""
        latest_url=""
        for ((i=0; i<${#lines[@]}; i+=2)); do
            date="${lines[i]}"
            url="${lines[i+1]}"
            if [[ "$date" > "$latest_date" ]]; then
                latest_date="$date"
                latest_url="$url"
            fi
        done

        if [ -z "$latest_url" ]; then
            echo "No release found for $mod_name"
            return 1
        fi

        full_url="https://mods.factorio.com$latest_url?username=$username&token=$token"

        file_name=$(basename "$latest_url")

        cd "$DOWNLOAD_DIR"

        echo "Downloading $file_name..."
        curl -k -L -o "$file_name" "$full_url"
    }

    mkdir -p "$DOWNLOAD_DIR"

    for mod in "${mods[@]}"; do
        download_latest_mod_version "$mod"
    done
    
    echo "Mods script completed."

else
    echo "Daemon detects server mode is 0."
    echo "Mods disabled, skipping script.."
    echo "Mods script completed."
fi

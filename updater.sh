# Copyright Delta Networks
# Author: Rhys

# Install to scripts, install script
# Start mod script

#!/bin/bash

version="1.1.0-"

if [[ "${ENABLE_MODS}" == "1" ]]; then
    echo "[Mod Manager] Daemon detects server mode is 1."
    echo "[Mod Manager] Mods enabled."
    echo "[Mod Manager] Starting Mod Manager $version."

    # Config
    username="${SERVER_USERNAME}"
    token="${SERVER_TOKEN}"
    DOWNLOAD_DIR="$(pwd)/mods"  # Use absolute path for DOWNLOAD_DIR

    # Input string of mod names (comma-separated)
    MOD_NAMES_STRING="${MOD_NAMES}"

    # Convert the comma-separated string into an array
    IFS=',' read -r -a mods <<< "$MOD_NAMES_STRING"

    # Function to check if a mod is already installed
    is_mod_installed() {
        mod_name=$1
        # Check if any folder in /mods/ starts with the mod name
        if [ -d "$DOWNLOAD_DIR/${mod_name}_"* ]; then
            return 0  # Mod is installed
        else
            return 1  # Mod is not installed
        fi
    }

    get_installed_version() {
        mod_name=$1
        # Find the mod folder and extract the version number
        mod_folder=$(ls -d "$DOWNLOAD_DIR/${mod_name}_"* 2>/dev/null)
        if [ -n "$mod_folder" ]; then
            echo "$mod_folder" | grep -oP '(?<=_)[0-9]+\.[0-9]+\.[0-9]+'
        else
            echo ""
        fi
    }

    # Function to add a mod to mod-list.json
    add_mod_to_list() {
        mod_name=$1
        mod_list_file="$DOWNLOAD_DIR/mod-list.json"

        # Create mod-list.json if it doesn't exist
        if [ ! -f "$mod_list_file" ]; then
            echo "[Mod Manager] Creating mod-list.json..."
            echo '{"mods": []}' > "$mod_list_file"
        fi

        # Check if the mod is already in the list
        if grep -q "\"name\": \"$mod_name\"" "$mod_list_file"; then
            echo "[Mod Manager] Mod $mod_name is already listed in mod-list.json."
        else
            echo "[Mod Manager] Adding $mod_name to mod-list.json..."

            # Use jq to add the mod to the list
            if command -v jq &>/dev/null; then
                # Use jq to add the mod entry
                jq ".mods += [{\"name\": \"$mod_name\", \"enabled\": true}]" "$mod_list_file" > "$mod_list_file.tmp" && mv "$mod_list_file.tmp" "$mod_list_file"
            else
                # Fallback to sed if jq is not available
                # Ensure the JSON structure is valid
                if [ ! -s "$mod_list_file" ]; then
                    echo '{"mods": []}' > "$mod_list_file"
                fi
                # Add the mod entry
                sed -i '/"mods": \[/a \    {\n      "name": "'"$mod_name"'",\n      "enabled": true\n    },' "$mod_list_file"
                # Remove the trailing comma from the last entry
                sed -i ':a;N;$!ba;s/,\n\s*\n\s*]/ \n    ]/g' "$mod_list_file"
            fi

            echo "[Mod Manager] Mod $mod_name added to mod-list.json."
        fi
    }

    # Function to remove a mod from mod-list.json
    remove_mod_from_list() {
        mod_name=$1
        mod_list_file="$DOWNLOAD_DIR/mod-list.json"

        if [ -f "$mod_list_file" ]; then
            echo "[Mod Manager] Removing $mod_name from mod-list.json..."

            # Use jq to remove the mod entry
            if command -v jq &>/dev/null; then
                jq "del(.mods[] | select(.name == \"$mod_name\"))" "$mod_list_file" > "$mod_list_file.tmp" && mv "$mod_list_file.tmp" "$mod_list_file"
            else
                # Fallback to sed if jq is not available
                sed -i "/\"name\": \"$mod_name\"/d" "$mod_list_file"
                # Clean up JSON structure
                sed -i ':a;N;$!ba;s/,\n\s*\]/ \n    ]/g' "$mod_list_file"
            fi

            echo "[Mod Manager] Mod $mod_name removed from mod-list.json."
        else
            echo "[Mod Manager] mod-list.json not found. Skipping removal of $mod_name."
        fi
    }

    # Function to remove unused mods
    remove_unused_mods() {
        echo "[Mod Manager] Checking for unused mods..."

        # List of files and folders to exclude from cleanup
        exclude_list=("mod-list.json" "mod-settings.dat")

        # Get the list of installed mods (only folders matching modname_version)
        installed_mods=($(ls -d "$DOWNLOAD_DIR/"* 2>/dev/null | grep -oP '(?<=/)[^/_]+(?=_[0-9]+\.[0-9]+\.[0-9]+)' | sort -u))

        for installed_mod in "${installed_mods[@]}"; do
            # Skip excluded files and folders
            if [[ " ${exclude_list[@]} " =~ " ${installed_mod} " ]]; then
                echo "[Mod Manager] Skipping excluded mod/folder: $installed_mod"
                continue
            fi

            # Check if the installed mod is still in the MOD_NAMES list
            if [[ ! " ${mods[@]} " =~ " ${installed_mod} " ]]; then
                echo "[Mod Manager] Mod $installed_mod is no longer in the list. Removing.."

                # Delete the mod folder
                if [ -d "$DOWNLOAD_DIR/${installed_mod}_"* ]; then
                    echo "[Mod Manager] Deleting mod folder for $installed_mod.."
                    rm -rf "$DOWNLOAD_DIR/${installed_mod}_"*
                fi

                # Remove the mod from mod-list.json
                remove_mod_from_list "$installed_mod"
            fi
        done

        echo "[Mod Manager] Mod cleanup complete."
    }

    # Function to download and install the latest mod version
    download_latest_mod_version() {
        mod_name=$1
        echo "[Mod Manager] Fetching latest version for $mod_name..."

        response=$(curl -s "https://mods.factorio.com/api/mods/$mod_name")

        # Extract the latest release's download_url, released_at, and version
        latest_url=$(echo "$response" | grep -oP '"download_url":"\K[^"]+' | tail -1)
        latest_date=$(echo "$response" | grep -oP '"released_at":"\K[^"]+' | tail -1)
        latest_version=$(echo "$response" | grep -oP '"version":"\K[^"]+' | tail -1)

        echo "[Mod Manager] Latest URL for $mod_name: $latest_url"
        echo "[Mod Manager] Latest release date for $mod_name: $latest_date"
        echo "[Mod Manager] Latest version for $mod_name: $latest_version"

        if [ -z "$latest_url" ]; then
            echo "[Mod Manager] No release found for $mod_name"
            return 1
        fi

        # Get the installed version (if any)
        installed_version=$(get_installed_version "$mod_name")

        if [ -n "$installed_version" ]; then
            echo "[Mod Manager] Installed version of $mod_name: $installed_version"
        else
            echo "[Mod Manager] Mod $mod_name is not installed."
        fi

        # Compare versions
        if [[ "$installed_version" == "$latest_version" ]]; then
            echo "[Mod Manager] Mod $mod_name is already up to date (version $latest_version). Skipping download."
            return 0
        elif [[ "$installed_version" < "$latest_version" ]]; then
            echo "[Mod Manager] New version of $mod_name available: $latest_version (installed: $installed_version). Downloading..."
        else
            echo "[Mod Manager] Installed version of $mod_name ($installed_version) is newer than the latest available ($latest_version). Skipping download."
            return 0
        fi

        full_url="https://mods.factorio.com$latest_url?username=$username&token=$token"

        file_name=$(basename "$latest_url")

        cd "$DOWNLOAD_DIR"

        # Delete the old version of the mod (if it exists)
        if [ -n "$installed_version" ]; then
            old_mod_folder="${mod_name}_${installed_version}"
            if [ -d "$old_mod_folder" ]; then
                echo "[Mod Manager] Deleting old version of $mod_name ($old_mod_folder)..."
                rm -rf "$old_mod_folder"
            fi
        fi

        echo "[Mod Manager] Downloading $file_name..."
        curl -k -L -o "$file_name" "$full_url"

        # Extract the mod archive to the correct directory
        echo "[Mod Manager] Extracting $file_name to $DOWNLOAD_DIR..."
        unzip -o "$file_name" -d .

        # Delete the archive after extraction
        echo "[Mod Manager] Deleting archive $file_name..."
        rm "$file_name"

        # Add the mod to mod-list.json
        add_mod_to_list "$mod_name"
    }

    # Remove unused mods
    remove_unused_mods

    # Process mods in the MOD_NAMES list
    for mod in "${mods[@]}"; do
        if is_mod_installed "$mod"; then
            echo "[Mod Manager] Mod $mod is installed. Checking for updates..."
            download_latest_mod_version "$mod"
        else
            echo "[Mod Manager] Mod $mod is not installed. Downloading latest version..."
            download_latest_mod_version "$mod"
        fi
    done

    if [[ "${ENABLE_MODS_DEBUG}" == "1" ]]; then
        # Debug Function
        echo "[Mod Manager - Debug] Username var: $username"
        echo "[Mod Manager - Debug] Token var: $token"
        echo "[Mod Manager - Debug] DOWNLOAD_DIR var: $DOWNLOAD_DIR"
        echo "[Mod Manager - Debug] MOD_NAMES_STRING var: $MOD_NAMES_STRING"
        echo "[Mod Manager - Debug] API Response for $mod_name: $response"
        echo "[Mod Manager - Debug] Latest URL for $mod_name: $latest_url"
        echo "[Mod Manager - Debug] Full URL: $full_url"
    else
        echo "[Mod Manager - Debug] Debug disabled, skipping.."
    fi
    
    echo "[Mod Manager] Mods loader functions complete."

else
    echo "[Mod Manager] Daemon detects server mode is 0."
    echo "[Mod Manager] Mods disabled, skipping.."
fi

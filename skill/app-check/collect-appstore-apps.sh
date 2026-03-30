#!/bin/bash

# Collect all App Store installed applications on macOS
# This script accurately identifies applications installed from the App Store

echo "Collecting App Store installed applications..."
echo "=============================================="
echo ""

# Create a temporary file to store results
TEMP_FILE=$(mktemp)
APP_COUNT=0

# Function to check if an app is from App Store
is_appstore_app() {
    local app_path="$1"

    # Method 1: Check for MAS receipt inside the app bundle
    # This is the most reliable indicator of an App Store installation
    if [ -f "$app_path/Contents/_MASReceipt/receipt" ]; then
        return 0
    fi

    # Method 2: Check code signing certificate for App Store signature
    # App Store apps are signed with "3rd Party Mac Developer Application" or "Apple Distribution"
    local signature=$(codesign -dv "$app_path" 2>&1 | grep "Authority=" | grep -iE "3rd Party Mac Developer Application|Apple Distribution" || echo "")
    if [ -n "$signature" ]; then
        return 0
    fi

    return 1
}

# Function to get app version
get_app_version() {
    local app_path="$1"
    local info_plist="$app_path/Contents/Info.plist"

    if [ -f "$info_plist" ]; then
        # Try to get the short version string first
        local version=$(plutil -extract "CFBundleShortVersionString" raw "$info_plist" 2>/dev/null)
        if [ -z "$version" ] || [ "$version" = "null" ]; then
            # Fall back to bundle version
            version=$(plutil -extract "CFBundleVersion" raw "$info_plist" 2>/dev/null)
        fi
        echo "$version"
    else
        echo "Unknown"
    fi
}

# Function to get the latest version from App Store
get_latest_appstore_version() {
    local app_name="$1"

    # Query iTunes Search API for the app (use curl's timeout option)
    curl -s --max-time 10 "https://itunes.apple.com/search?term=$(echo "$app_name" | tr ' ' '+')&country=US&entity=software&limit=1" 2>/dev/null | \
        jq -r '.results[0].version' 2>/dev/null | \
        grep -v "null" || echo "N/A"
}

# Search in /Applications
if [ -d "/Applications" ]; then
    echo "Scanning /Applications..."
    for app in /Applications/*.app; do
        if [ -e "$app" ]; then
            if is_appstore_app "$app"; then
                app_name=$(basename "$app" .app)
                version=$(get_app_version "$app")
                echo "Fetching latest version for $app_name..." >&2
                latest_version=$(get_latest_appstore_version "$app_name")
                echo "$app_name|$version|$latest_version" >> "$TEMP_FILE"
                ((APP_COUNT++))
            fi
        fi
    done
fi

# Search in ~/Applications
if [ -d "$HOME/Applications" ]; then
    echo "Scanning ~/Applications..."
    for app in "$HOME/Applications"/*.app; do
        if [ -e "$app" ]; then
            if is_appstore_app "$app"; then
                app_name=$(basename "$app" .app)
                version=$(get_app_version "$app")
                echo "Fetching latest version for $app_name..." >&2
                latest_version=$(get_latest_appstore_version "$app_name")
                echo "$app_name|$version|$latest_version" >> "$TEMP_FILE"
                ((APP_COUNT++))
            fi
        fi
    done
fi

# Display results
echo ""
echo "Found $APP_COUNT App Store applications:"
echo "========================================"
if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
    echo ""
    echo "Application Name                          | Current | Latest"
    echo "------------------------------------------|---------|----------"
    sort "$TEMP_FILE" | uniq | while IFS='|' read name version latest; do
        printf "%-40s | %-7s | %s\n" "$name" "$version" "$latest"
    done
else
    echo "No App Store applications detected."
fi

# Save results to a file in home directory
OUTPUT_FILE="$HOME/appstore-apps-$(date +%Y%m%d-%H%M%S).txt"
if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
    {
        echo "App Store Installed Applications"
        echo "Generated: $(date)"
        echo ""
        echo "Total Found: $APP_COUNT"
        echo ""
        echo "Application Name                          | Current | Latest"
        echo "------------------------------------------|---------|----------"
        sort "$TEMP_FILE" | uniq | while IFS='|' read name version latest; do
            printf "%-40s | %-7s | %s\n" "$name" "$version" "$latest"
        done
    } > "$OUTPUT_FILE"
    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Done!"

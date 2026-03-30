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

# Search in /Applications
if [ -d "/Applications" ]; then
    echo "Scanning /Applications..."
    for app in /Applications/*.app; do
        if [ -e "$app" ]; then
            if is_appstore_app "$app"; then
                app_name=$(basename "$app" .app)
                echo "$app_name" >> "$TEMP_FILE"
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
                echo "$app_name" >> "$TEMP_FILE"
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
    sort "$TEMP_FILE" | uniq
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
        sort "$TEMP_FILE" | uniq
    } > "$OUTPUT_FILE"
    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Done!"

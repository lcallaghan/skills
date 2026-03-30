#!/bin/bash

# Collect all App Store installed applications on macOS
# This script finds applications and identifies which ones were installed from the App Store

echo "Collecting App Store installed applications..."
echo "=============================================="
echo ""

# Create a temporary file to store results
TEMP_FILE=$(mktemp)
APP_COUNT=0

# Function to check if an app is from App Store
check_appstore() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)

    # Check for App Store indicators using mdls
    if mdls -name kMDItemAppStoreCategory "$app_path" 2>/dev/null | grep -q "."; then
        echo "$app_name" >> "$TEMP_FILE"
        ((APP_COUNT++))
        return 0
    fi

    # Alternative check: look for App Store receipt
    local bundle_id=$(mdls -name kMDItemCFBundleIdentifier "$app_path" 2>/dev/null | cut -d'"' -f2)
    if [ -n "$bundle_id" ]; then
        local receipt_path="$HOME/Library/Receipts/InstallHistory.plist"
        if plutil -p "$receipt_path" 2>/dev/null | grep -q "$bundle_id"; then
            echo "$app_name" >> "$TEMP_FILE"
            ((APP_COUNT++))
            return 0
        fi
    fi

    return 1
}

# Search in /Applications
if [ -d "/Applications" ]; then
    echo "Searching /Applications..."
    for app in /Applications/*.app; do
        [ -e "$app" ] && check_appstore "$app"
    done
fi

# Search in ~/Applications
if [ -d "$HOME/Applications" ]; then
    echo "Searching ~/Applications..."
    for app in "$HOME/Applications"/*.app; do
        [ -e "$app" ] && check_appstore "$app"
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
    sort "$TEMP_FILE" | uniq > "$OUTPUT_FILE"
    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Done!"

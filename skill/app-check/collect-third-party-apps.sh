#!/bin/bash

# Collect all third-party (non-App Store) installed applications on macOS
# This script finds applications installed from DMG, PKG, or other sources

echo "Collecting third-party installed applications..."
echo "=================================================="
echo ""

# Create temporary files
TEMP_FILE=$(mktemp)
APP_COUNT=0

# Function to check if an app is legitimately from App Store
is_appstore_app() {
    local app_path="$1"
    local bundle_id=$(mdls -name kMDItemCFBundleIdentifier "$app_path" 2>/dev/null | cut -d'"' -f2)

    if [ -z "$bundle_id" ]; then
        return 1
    fi

    # Check if the app is signed by Apple (App Store apps have specific signature)
    local signature=$(codesign -dv "$app_path" 2>&1 | grep "Authority=" | grep -i "app store" || echo "")
    if [ -n "$signature" ]; then
        return 0
    fi

    # Check for App Store receipt in the app bundle
    if [ -f "$app_path/Contents/_MASReceipt/receipt" ]; then
        return 0
    fi

    # Check Receipt database
    local receipt_path="$HOME/Library/Receipts/InstallHistory.plist"
    if [ -f "$receipt_path" ]; then
        # This is more thorough checking
        if plutil -extract "InstallHistory" xml1 "$receipt_path" 2>/dev/null | \
           grep -q "\.app</string>" && \
           basename "$app_path" | grep -q "$(basename "$app_path")"; then
            return 0
        fi
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

# Function to detect installation source
get_install_source() {
    local app_path="$1"
    local app_name=$(basename "$app_path" .app)

    # Check for Homebrew Cask installation
    if [ -d "$HOME/.local/share/applications" ]; then
        if find "$HOME/.local/share/applications" -type l -name "*.desktop" 2>/dev/null | xargs grep -l "$app_name" 2>/dev/null | grep -q "."; then
            echo "Homebrew"
            return
        fi
    fi

    # Check for Homebrew in path
    if [ -L "$app_path" ] || [ -d "$app_path/../.." ] && echo "$app_path" | grep -q "Cellar\|Caskroom"; then
        echo "Homebrew"
        return
    fi

    # Check /opt/homebrew
    if echo "$app_path" | grep -q "/opt/homebrew"; then
        echo "Homebrew"
        return
    fi

    # Check code signing certificate
    local cert=$(codesign -dv "$app_path" 2>&1 | grep "Authority=" | head -1 | cut -d'=' -f2-)
    if echo "$cert" | grep -qi "developer\|personal"; then
        echo "Developer"
        return
    fi

    # Check for DMG marker or standard installation
    echo "Direct Install/DMG"
}

# Get all installed applications - more comprehensive search
find /Applications -maxdepth 1 -type d -name "*.app" 2>/dev/null | while read app; do
    if [ -e "$app" ]; then
        if ! is_appstore_app "$app"; then
            app_name=$(basename "$app" .app)
            install_source=$(get_install_source "$app")
            version=$(get_app_version "$app")
            echo "$app_name|$install_source|$version" >> "$TEMP_FILE"
            ((APP_COUNT++))
        fi
    fi
done

# Also check ~/Applications
if [ -d "$HOME/Applications" ]; then
    find "$HOME/Applications" -maxdepth 1 -type d -name "*.app" 2>/dev/null | while read app; do
        if [ -e "$app" ]; then
            if ! is_appstore_app "$app"; then
                app_name=$(basename "$app" .app)
                install_source=$(get_install_source "$app")
                version=$(get_app_version "$app")
                echo "$app_name|$install_source|$version" >> "$TEMP_FILE"
                ((APP_COUNT++))
            fi
        fi
    done
fi

# Check for Homebrew Cask applications
if command -v brew &> /dev/null; then
    echo "Scanning Homebrew Cask installations..."
    brew list --cask 2>/dev/null | while read app; do
        if [ -n "$app" ]; then
            # Check if app exists in standard locations
            if [ ! -d "/Applications/$app.app" ] && [ ! -d "$HOME/Applications/$app.app" ]; then
                # Look for it in brew locations
                app_path=$(find "$(brew --prefix)/Caskroom" -maxdepth 2 -type d -name "$app.app" 2>/dev/null | head -1)
                if [ -n "$app_path" ] && [ -d "$app_path" ]; then
                    version=$(get_app_version "$app_path")
                    echo "$app|Homebrew Cask|$version" >> "$TEMP_FILE"
                fi
            fi
        fi
    done
fi

# Count total found
if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
    APP_COUNT=$(wc -l < "$TEMP_FILE")
else
    APP_COUNT=0
fi

# Display results
echo ""
echo "Found $APP_COUNT third-party applications:"
echo "=========================================="
echo ""

if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
    # Sort and display with sources and versions
    echo "Application Name                          | Installation Source    | Version"
    echo "------------------------------------------|------------------------|------------------"
    sort -u "$TEMP_FILE" | while IFS='|' read app source version; do
        printf "%-40s | %-24s | %s\n" "$app" "$source" "$version"
    done
else
    echo "No third-party applications detected."
fi

# Save detailed results to a file
OUTPUT_FILE="$HOME/third-party-apps-$(date +%Y%m%d-%H%M%S).txt"
if [ -f "$TEMP_FILE" ] && [ -s "$TEMP_FILE" ]; then
    {
        echo "Third-Party Applications Report"
        echo "Generated: $(date)"
        echo ""
        echo "Total Found: $APP_COUNT"
        echo ""
        echo "Application Name                          | Installation Source    | Version"
        echo "------------------------------------------|------------------------|------------------"
        sort -u "$TEMP_FILE" | while IFS='|' read app source version; do
            printf "%-40s | %-24s | %s\n" "$app" "$source" "$version"
        done
    } > "$OUTPUT_FILE"

    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Done!"

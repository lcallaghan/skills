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

# Function to get latest version from various sources
get_latest_version() {
    local app_name="$1"
    local version=""

    # Try various APIs for version detection
    case "$app_name" in
        "Visual Studio Code"|"Code")
            version=$(curl -s --max-time 10 "https://api.github.com/repos/microsoft/vscode/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
            [ -n "$version" ] && echo "$version" && return
            ;;
        "Firefox")
            # Firefox - use Mozilla product details API
            version=$(curl -s --max-time 10 "https://product-details.mozilla.org/1.0/firefox_versions.json" 2>/dev/null | jq -r '.LATEST_FIREFOX_VERSION // empty' 2>/dev/null)
            [ -n "$version" ] && echo "$version" && return
            ;;
        "Docker")
            # Docker moved to moby/moby repo
            version=$(curl -s --max-time 10 "https://api.github.com/repos/moby/moby/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^docker-v//' | sed 's/-.*//')
            [ -n "$version" ] && echo "$version" && return
            ;;
        "draw.io")
            version=$(curl -s --max-time 10 "https://api.github.com/repos/jgraph/drawio/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
            [ -n "$version" ] && echo "$version" && return
            ;;
    esac

    echo "N/A"
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
            echo "Fetching latest version for $app_name..." >&2
            latest=$(get_latest_version "$app_name")
            echo "$app_name|$install_source|$version|$latest" >> "$TEMP_FILE"
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
                echo "Fetching latest version for $app_name..." >&2
                latest=$(get_latest_version "$app_name")
                echo "$app_name|$install_source|$version|$latest" >> "$TEMP_FILE"
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
                    echo "Fetching latest version for $app..." >&2
                    latest=$(get_latest_version "$app")
                    echo "$app|Homebrew Cask|$version|$latest" >> "$TEMP_FILE"
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
    # Sort and display with sources, versions, and latest
    echo "Application Name                          | Source      | Current | Latest"
    echo "------------------------------------------|-------------|---------|----------"
    sort -u "$TEMP_FILE" | while IFS='|' read app source version latest; do
        printf "%-40s | %-11s | %-7s | %s\n" "$app" "$source" "$version" "$latest"
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
        echo "Application Name                          | Source      | Current | Latest"
        echo "------------------------------------------|-------------|---------|----------"
        sort -u "$TEMP_FILE" | while IFS='|' read app source version latest; do
            printf "%-40s | %-11s | %-7s | %s\n" "$app" "$source" "$version" "$latest"
        done
    } > "$OUTPUT_FILE"

    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

# Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "Done!"

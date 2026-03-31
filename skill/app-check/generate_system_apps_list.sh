#!/bin/bash

# Script to extract and consolidate system applications from inventory file
# and scan for additional system applications

INVENTORY_FILE="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/full_application_inventory.txt"
OUTPUT_FILE="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/outapps.txt"

echo "Generating System Applications List..."
echo ""

# Temporary file for storing all bundles
TEMP_FILE=$(mktemp)

# Extract SYSTEM APPLICATIONS from inventory file
echo "Reading system applications from inventory file..."
if [ -f "$INVENTORY_FILE" ]; then
    # Extract lines between SYSTEM APPLICATIONS header and the next /System/Applications detail section
    # Look for app names ending in .app or "Utilities" directory
    awk '/^=== SYSTEM APPLICATIONS/,/^\/System\/Applications\/App Store\.app:/ {
        if (/\.app$/ && !/^===/ && !/^==/ && !/^\/System/ && !/^Contents/) {
            print "/System/Applications/" $0
        }
    }' "$INVENTORY_FILE" | sort -u >> "$TEMP_FILE"
else
    echo "Error: Inventory file not found at $INVENTORY_FILE"
    exit 1
fi

# Scan /System/Applications/Utilities for bundles
echo "Scanning /System/Applications/Utilities for bundles..."
if [ -d "/System/Applications/Utilities" ]; then
    find "/System/Applications/Utilities" -maxdepth 1 -type d -name "*.app" | sort >> "$TEMP_FILE"
fi

# Scan for other directories under /System/Applications (besides known system folders)
echo "Scanning for other directories under /System/Applications..."
KNOWN_DIRS=("Applications" "Utilities" "Resources" "Contents" "PlugIns" "Frameworks")
OTHER_APPS_TEMP=$(mktemp)

for dir in /System/Applications/*/; do
    dir_name=$(basename "$dir")

    # Skip if it's a bundle (ends with .app, .bundle, etc.)
    if [[ "$dir_name" =~ \.(app|bundle|framework|docktileplugin)$ ]]; then
        continue
    fi

    # Skip known system directories
    skip=0
    for known in "${KNOWN_DIRS[@]}"; do
        if [ "$dir_name" = "$known" ]; then
            skip=1
            break
        fi
    done

    if [ $skip -eq 1 ]; then
        continue
    fi

    # Found a non-standard directory, search for bundles inside it
    echo "Found other directory: $dir_name, scanning for bundles..."
    find "$dir" -maxdepth 1 -type d \( -name "*.app" -o -name "*.bundle" \) | sort >> "$OTHER_APPS_TEMP"
done

# Remove duplicates and sort
SORTED_FILE=$(mktemp)
sort -u "$TEMP_FILE" > "$SORTED_FILE"

# Count applications
APP_COUNT=$(wc -l < "$SORTED_FILE")

# Generate output file
{
    echo "====================================================================================="
    echo "=== SYSTEM APPLICATIONS (/System/Applications) and /System/Applications/Utilities ==="
    echo "====================================================================================="
    echo ""
    cat "$SORTED_FILE"
    echo ""

    # Check if there are other applications
    OTHER_APP_COUNT=$(wc -l < "$OTHER_APPS_TEMP" 2>/dev/null | awk '{print $1}')
    if [ "$OTHER_APP_COUNT" -gt 0 ]; then
        echo "================================="
        echo "=== OTHER SYSTEM APPLICATIONS ==="
        echo "================================="
        echo ""
        sort -u "$OTHER_APPS_TEMP"
    else
        echo "================================="
        echo "=== OTHER SYSTEM APPLICATIONS ==="
        echo "================================="
        echo ""
        echo "No Applications Found"
    fi
} > "$OUTPUT_FILE"

# Display results
echo ""
echo "=========================================="
echo "Generation Complete"
echo "=========================================="
echo ""
echo "Total SYSTEM APPLICATIONS found: $APP_COUNT"
echo "Output file: $OUTPUT_FILE"
echo ""

# Clean up
rm -f "$TEMP_FILE" "$OTHER_APPS_TEMP" "$SORTED_FILE"

# Display the output
echo "Preview of generated file:"
echo ""
head -30 "$OUTPUT_FILE"
echo "..."
echo ""
echo "Done!"

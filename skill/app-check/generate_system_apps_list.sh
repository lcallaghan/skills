#!/bin/bash

# Script to extract and consolidate system applications from inventory file
# and scan for additional system applications

INVENTORY_FILE="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/full_application_inventory.txt"
OUTPUT_NO_SYSTEM="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/output-nosystem.txt"
OUTPUT_FILE="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/outapps.txt"
OUTPUT_APPS_LIBRARY="/Users/lancecallaghan/Cowork-Skill/skills/skill/app-check/output-nosystem-apps-library.txt"

echo "Generating System Applications List..."
echo ""

# Temporary files for storing all bundles
TEMP_FILE=$(mktemp)
TEMP_LIBRARY_FILE=$(mktemp)

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

# Extract System Library applications from output-nosystem.txt
echo "Extracting System Library applications from inventory..."
grep "^/System/Library.*\.\(app\|bundle\|framework\|docktileplugin\)$" "$OUTPUT_NO_SYSTEM" | sort -u >> "$TEMP_LIBRARY_FILE"

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

SORTED_LIBRARY_FILE=$(mktemp)
sort -u "$TEMP_LIBRARY_FILE" > "$SORTED_LIBRARY_FILE"

# Count applications
APP_COUNT=$(wc -l < "$SORTED_FILE")
LIBRARY_APP_COUNT=$(wc -l < "$SORTED_LIBRARY_FILE" 2>/dev/null)

# Generate output file with System Applications and System Library Applications
{
    echo "====================================================================================="
    echo "=== SYSTEM APPLICATIONS (/System/Applications) and /System/Applications/Utilities ==="
    echo "====================================================================================="
    echo ""
    cat "$SORTED_FILE"
    echo ""

    # Add System Library Applications section if any exist
    if [ "$LIBRARY_APP_COUNT" -gt 0 ]; then
        echo "=================================================="
        echo "=== SYSTEM LIBRARY APPLICATIONS (/System/Library) ==="
        echo "=================================================="
        echo ""
        cat "$SORTED_LIBRARY_FILE"
        echo ""
    fi

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

# Generate output file without system applications
echo "Creating inventory file without system applications..."
{
    # Read the inventory file and remove SYSTEM APPLICATIONS section and all related content
    awk '
    BEGIN {
        in_system_section = 0
    }
    /^=== SYSTEM APPLICATIONS/ {
        # Found the start of the SYSTEM APPLICATIONS section, skip until next section header
        in_system_section = 1
        next
    }
    /^=== SYSTEM LIBRARY APPS/ {
        # Found the next section, print it and continue normally
        in_system_section = 0
        print
        next
    }
    in_system_section {
        # Skip everything in the SYSTEM APPLICATIONS section
        next
    }
    /^\/System\/Applications\// {
        # Skip any lines starting with /System/Applications (the detailed listing)
        next
    }
    {
        print
    }
    ' "$INVENTORY_FILE"
} > "$OUTPUT_NO_SYSTEM"

# Generate output file without system applications AND system library applications
echo "Creating inventory file without system applications and library applications..."
{
    # Read the inventory file and remove both SYSTEM APPLICATIONS and SYSTEM LIBRARY APPS sections
    awk '
    BEGIN {
        in_system_app_section = 0
        in_system_library_section = 0
    }
    /^=== SYSTEM APPLICATIONS/ {
        in_system_app_section = 1
        next
    }
    /^=== SYSTEM LIBRARY APPS/ {
        # Switch from system applications to system library section
        in_system_app_section = 0
        in_system_library_section = 1
        next
    }
    /^=== CORE SERVICES/ {
        # Found the next section after library, print it and continue normally
        in_system_library_section = 0
        print
        next
    }
    in_system_app_section || in_system_library_section {
        # Skip everything in both sections
        next
    }
    /^\/System\/Applications\// || /^\/System\/Library\// {
        # Skip any lines starting with /System/Applications or /System/Library (the detailed listings)
        next
    }
    {
        print
    }
    ' "$INVENTORY_FILE"
} > "$OUTPUT_APPS_LIBRARY"

# Display results
echo ""
echo "=========================================="
echo "Generation Complete"
echo "=========================================="
echo ""
echo "Total SYSTEM APPLICATIONS found: $APP_COUNT"
echo "Total SYSTEM LIBRARY APPLICATIONS found: $LIBRARY_APP_COUNT"
echo ""
echo "Output files:"
echo "  - $OUTPUT_FILE (all system apps)"
echo "  - $OUTPUT_NO_SYSTEM (no system apps)"
echo "  - $OUTPUT_APPS_LIBRARY (no system or library apps)"
echo ""

# Clean up
rm -f "$TEMP_FILE" "$OTHER_APPS_TEMP" "$SORTED_FILE" "$TEMP_LIBRARY_FILE" "$SORTED_LIBRARY_FILE"

# Display the output
echo "Preview of generated file (outapps.txt):"
echo ""
head -30 "$OUTPUT_FILE"
echo "..."
echo ""
echo "Done!"

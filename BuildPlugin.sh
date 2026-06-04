#!/bin/bash
# VibeUE Plugin Build Script for Mac/Linux
#
# Usage:
#   ./BuildPlugin.sh                        # auto-detect UE installation
#   ./BuildPlugin.sh /path/to/UE_5.7       # explicit UE path
#
# Place this script in the VibeUE plugin root (alongside VibeUE.uplugin) for
# best results. If a .uproject is found by walking up the directory tree, the
# plugin is built in project context for maximum compatibility. Otherwise falls
# back to a standalone UAT BuildPlugin build.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect platform ────────────────────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
    PLATFORM="Mac"
    PLATFORM_BUILD_SUBPATH="Engine/Build/BatchFiles/Mac/Build.sh"
    PLATFORM_UAT_SUBPATH="Engine/Build/BatchFiles/RunUAT.sh"
    DEFAULT_EPIC_DIR="/Users/Shared/Epic Games"
else
    PLATFORM="Linux"
    PLATFORM_BUILD_SUBPATH="Engine/Build/BatchFiles/Linux/Build.sh"
    PLATFORM_UAT_SUBPATH="Engine/Build/BatchFiles/RunUAT.sh"
    DEFAULT_EPIC_DIR=""
fi

echo ""
echo "===================================="
echo " VibeUE Plugin Build Script"
echo " Platform: $PLATFORM"
echo "===================================="
echo ""

# ── Find .uplugin ─────────────────────────────────────────────────────────────
UPLUGIN_PATH=$(find "$PLUGIN_DIR" -maxdepth 1 -name "*.uplugin" | head -1)
if [[ -z "$UPLUGIN_PATH" ]]; then
    echo "ERROR: Could not find .uplugin file in $PLUGIN_DIR"
    exit 1
fi
PLUGIN_NAME=$(basename "$UPLUGIN_PATH" .uplugin)
echo "Plugin: $PLUGIN_NAME"

# ── Resolve UE path ───────────────────────────────────────────────────────────
UE_PATH=""

# 1. Explicit parameter
if [[ -n "${1:-}" ]]; then
    echo "Checking provided path: $1"
    if [[ -f "$1/$PLATFORM_BUILD_SUBPATH" ]]; then
        UE_PATH="$1"
        echo "Using provided UE path: $UE_PATH"
    else
        echo "WARNING: $1 is not a valid UE installation (missing $PLATFORM_BUILD_SUBPATH)"
        echo "Falling back to auto-detection..."
        echo ""
    fi
fi

# 2. Auto-detect: read EngineAssociation from nearest .uproject
if [[ -z "$UE_PATH" ]]; then
    UE_VERSION=""
    SEARCH="$PLUGIN_DIR"
    for _ in {1..5}; do
        UPROJECT=$(find "$SEARCH" -maxdepth 1 -name "*.uproject" 2>/dev/null | head -1)
        if [[ -n "$UPROJECT" ]]; then
            UE_VERSION=$(grep -o '"EngineAssociation"[[:space:]]*:[[:space:]]*"[^"]*"' "$UPROJECT" \
                | grep -oE '[0-9]+\.[0-9]+')
            [[ -n "$UE_VERSION" ]] && echo "Detected engine version $UE_VERSION from $(basename "$UPROJECT")"
            break
        fi
        SEARCH=$(dirname "$SEARCH")
    done

    # 3. Check standard Epic Games install location
    if [[ -n "$UE_VERSION" && -n "$DEFAULT_EPIC_DIR" ]]; then
        CANDIDATE="$DEFAULT_EPIC_DIR/UE_$UE_VERSION"
        if [[ -f "$CANDIDATE/$PLATFORM_BUILD_SUBPATH" ]]; then
            UE_PATH="$CANDIDATE"
            echo "Found UE $UE_VERSION at: $UE_PATH"
        fi
    fi

    # 4. Scan Epic Games folder for any UE 5.x installation
    if [[ -z "$UE_PATH" && -n "$DEFAULT_EPIC_DIR" && -d "$DEFAULT_EPIC_DIR" ]]; then
        echo "Scanning $DEFAULT_EPIC_DIR for UE installations..."
        for DIR in "$DEFAULT_EPIC_DIR"/UE_5.*; do
            if [[ -f "$DIR/$PLATFORM_BUILD_SUBPATH" ]]; then
                UE_PATH="$DIR"
                echo "Found: $UE_PATH"
                break
            fi
        done
    fi

    # 5. Linux: check common source-build locations
    if [[ -z "$UE_PATH" && "$PLATFORM" == "Linux" ]]; then
        for CANDIDATE in \
            "$HOME/UnrealEngine" \
            "/opt/UnrealEngine" \
            "/usr/local/UnrealEngine"; do
            if [[ -f "$CANDIDATE/$PLATFORM_BUILD_SUBPATH" ]]; then
                UE_PATH="$CANDIDATE"
                echo "Found UE at: $UE_PATH"
                break
            fi
        done
    fi
fi

if [[ -z "$UE_PATH" ]]; then
    echo ""
    echo "ERROR: Could not find an Unreal Engine installation."
    echo ""
    echo "Options:"
    echo "  1. Pass the path explicitly:  $0 /path/to/UE_5.7"
    if [[ "$PLATFORM" == "Mac" ]]; then
        echo "  2. Install via Epic Games Launcher to: /Users/Shared/Epic Games/UE_5.x"
    else
        echo "  2. Set up a source build and place it at ~/UnrealEngine or /opt/UnrealEngine"
    fi
    exit 1
fi

BUILD_SCRIPT="$UE_PATH/$PLATFORM_BUILD_SUBPATH"
UAT_SCRIPT="$UE_PATH/$PLATFORM_UAT_SUBPATH"
UE_LABEL=$(basename "$UE_PATH")

echo ""
echo "Engine:  $UE_LABEL"
echo "Location: $UE_PATH"

# ── Find .uproject ─────────────────────────────────────────────────────────────
PROJECT_FILE=""
SEARCH="$PLUGIN_DIR"
for _ in {1..5}; do
    FOUND=$(find "$SEARCH" -maxdepth 1 -name "*.uproject" 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        PROJECT_FILE="$FOUND"
        break
    fi
    SEARCH=$(dirname "$SEARCH")
done

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
if [[ -n "$PROJECT_FILE" ]]; then
    PROJECT_NAME=$(basename "$PROJECT_FILE" .uproject)
    echo "Project: $PROJECT_NAME ($(dirname "$PROJECT_FILE"))"
    echo "Building plugin in project context..."
    echo ""
    "$BUILD_SCRIPT" "${PROJECT_NAME}Editor" "$PLATFORM" Development "$PROJECT_FILE" -WaitMutex
else
    echo "No .uproject found — building standalone via UAT BuildPlugin..."
    echo "NOTE: Standalone builds may cause 'Missing Modules' errors in some projects."
    echo "      For best results place this script inside YourProject/Plugins/VibeUE/"
    echo ""
    "$UAT_SCRIPT" BuildPlugin \
        -Plugin="$UPLUGIN_PATH" \
        -Package="$PLUGIN_DIR/Packaged" \
        -CreateSubFolder \
        -TargetPlatforms="$PLATFORM"
fi

echo ""
echo "===================================="
echo " Build Succeeded"
echo "===================================="
echo ""

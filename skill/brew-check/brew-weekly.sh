#!/bin/bash

LOG=~/Cowork/brew-weekly.log
DIVIDER="=================================================="

{
  echo ""
  echo "$DIVIDER"
  echo "BREW MAINTENANCE RUN: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "$DIVIDER"

  echo ""
  echo "--- UPDATE ---"
  brew update

  echo ""
  echo "--- OUTDATED PACKAGES (before upgrade) ---"
  brew outdated --verbose

  echo ""
  echo "--- UPGRADE ---"
  brew upgrade

  echo ""
  echo "--- CASK UPGRADE ---"
  brew upgrade --cask

  echo ""
  echo "--- CLEANUP ---"
  brew cleanup -s

  echo ""
  echo "--- BREW DOCTOR ---"
  brew doctor

  echo ""
  echo "--- AUTOREMOVE ---"
  brew autoremove

  echo ""
  echo "END OF RUN: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "$DIVIDER"
} >> "$LOG" 2>&1
#!/usr/bin/env bash
set -euo pipefail

repository_url="https://github.com/crisantus/gold-flutter.git"

if ! command -v dart >/dev/null 2>&1; then
  echo "Dart was not found. Install Flutter first: https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Git was not found. Install Git and run this installer again." >&2
  exit 1
fi

dart pub global activate --source git --git-ref main "$repository_url"

echo
echo "Gold Flutter is installed."
echo "Run: gold_flutter doctor"
echo "Then move to a parent folder and run: gold_flutter create"
echo
echo 'If gold_flutter is not found, add $HOME/.pub-cache/bin to PATH.'

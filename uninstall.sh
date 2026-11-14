#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/aria2-onedrive"
cd "$BASE"
docker compose down
if [[ "${1:-}" == "--purge" ]]; then
  echo "Removing ALL downloads, Aria2 state and rclone credentials in $BASE"
  rm -rf "$BASE"
else
  echo "Containers removed. Data and credentials preserved at $BASE."
  echo "To permanently delete them, run: $0 --purge"
fi

#!/usr/bin/env bash
# Download + extract the INCLUDE Indian Sign Language dataset (Zenodo 4010759)
# curl version -- works in Git Bash on Windows (no wget required)
#
# Each archive is handled end to end before the next one starts:
#   download -> verify -> extract -> delete zip
# so disk use stays flat instead of accumulating 57 GB of zips.
#
#   Total download : ~57 GB
#   Peak disk use  : ~59 GB with --purge  (extracted video + one zip in flight)
#                    ~115 GB without
#
# Usage (from Git Bash):
#   bash download_include.sh --purge
#   OUT=/d/isl_data bash download_include.sh --purge
#   bash download_include.sh --verify            # check existing zips, extract nothing
#   ONLY=Greetings,Pronouns bash download_include.sh --purge   # just some categories
#
# Safe to re-run: extracted archives are skipped, partial downloads resume.

set -uo pipefail

BASE="https://zenodo.org/records/4010759/files"
OUT="${OUT:-$PWD/include_data}"
ONLY="${ONLY:-}"
PURGE=0
VERIFY_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --purge)  PURGE=1 ;;
    --verify) VERIFY_ONLY=1 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

command -v curl  >/dev/null || { echo "curl not found"; exit 1; }
command -v unzip >/dev/null || { echo "unzip not found"; exit 1; }

CATEGORIES=(
  "Adjectives:8"
  "Animals:2"
  "Clothes:2"
  "Colours:2"
  "Days_and_Time:3"
  "Electronics:2"
  "Greetings:2"
  "Home:4"
  "Jobs:2"
  "Means_of_Transportation:2"
  "People:5"
  "Places:4"
  "Pronouns:2"
  "Seasons:1"
  "Society:3"
)

mkdir -p "$OUT/zips" "$OUT/videos" || exit 1
cd "$OUT/zips" || exit 1
echo "writing to: $OUT"

# --- build the file list ----------------------------------------------------
FILES=()
for entry in "${CATEGORIES[@]}"; do
  name="${entry%%:*}"
  parts="${entry##*:}"
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *",$name,"*) ;;
      *) continue ;;
    esac
  fi
  for i in $(seq 1 "$parts"); do
    FILES+=("${name}_${i}of${parts}.zip")
  done
done

TOTAL=${#FILES[@]}
[ "$TOTAL" -eq 0 ] && { echo "no archives selected"; exit 1; }
echo "$TOTAL archives to process"
echo

# --- main loop: one archive fully handled at a time -------------------------
n=0
FAILED=()
for f in "${FILES[@]}"; do
  n=$((n+1))
  tag="[$n/$TOTAL]"

  if [ -f "$OUT/videos/.done_$f" ]; then
    echo "$tag done already: $f"
    continue
  fi

  # ---- download (resume if partial) ----
  if [ -f "$f" ] && unzip -tqq "$f" >/dev/null 2>&1; then
    echo "$tag already downloaded: $f"
  else
    echo "$tag downloading $f"
    for attempt in 1 2 3; do
      curl -L -C - \
           --retry 10 --retry-delay 15 --retry-connrefused \
           --connect-timeout 60 \
           -o "$f" "$BASE/$f?download=1"
      # verify right away -- a truncated zip otherwise fails silently
      if unzip -tqq "$f" >/dev/null 2>&1; then
        break
      fi
      echo "    incomplete after attempt $attempt; retrying"
      sleep 10
    done
  fi

  if ! unzip -tqq "$f" >/dev/null 2>&1; then
    echo "    GAVE UP on $f -- re-run the script to try again"
    FAILED+=("$f")
    continue
  fi

  if [ "$VERIFY_ONLY" -eq 1 ]; then
    echo "    ok (verify-only, not extracting)"
    continue
  fi

  # ---- extract ----
  echo "    extracting"
  if unzip -q -n "$f" -d "$OUT/videos"; then
    touch "$OUT/videos/.done_$f"
    if [ "$PURGE" -eq 1 ]; then
      rm -f "$f"
      echo "    extracted, zip deleted"
    else
      echo "    extracted"
    fi
  else
    echo "    EXTRACTION FAILED for $f"
    FAILED+=("$f")
    continue
  fi

  # ---- progress ----
  done_n=$(ls "$OUT/videos"/.done_* 2>/dev/null | wc -l)
  used=$(du -sh "$OUT/videos" 2>/dev/null | cut -f1)
  free=$(df -Pk . 2>/dev/null | awk 'NR==2 {printf "%.0f", $4/1048576}')
  echo "    progress: $done_n/$TOTAL archives | videos: ${used:-?} | free: ${free:-?} GB"
  echo
done

# --- summary ----------------------------------------------------------------
echo
echo "=== finished pass"
vids=$(find "$OUT/videos" -type f \( -iname '*.mp4' -o -iname '*.mov' \) 2>/dev/null | wc -l)
echo "videos : $vids   (expect 4292 for the full dataset)"
echo "folder : $OUT/videos"
du -sh "$OUT/videos" 2>/dev/null

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo
  echo "${#FAILED[@]} archive(s) did not complete:"
  printf '  %s\n' "${FAILED[@]}"
  echo "Re-run the same command to retry them."
fi

echo
echo "Train/test split is separate from these archives:"
echo "  https://drive.google.com/file/d/1tGjOR9xbk279ZUYnmk3BE-ktcWBdS24w/view"
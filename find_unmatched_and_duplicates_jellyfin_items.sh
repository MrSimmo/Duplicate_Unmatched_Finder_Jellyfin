#!/bin/sh

# Tool to find unmatched items and/or duplicates in a Jellyfin library
# Requires: curl, jq

set -e

# --- Configure these ---
# To get your API key - log in to Jellyfin with an superuser/admin account and then click dashboard then API keys
# Then Get new key...
JellyfinURL="http://192.168.0.1:8096"
APIKEY="123456789"
# -----------------------

echo ""
echo "Tool to find unmatched and/or duplicate items in a Jellyfin Library"
echo "-------------------------------------------------------------------"
echo ""

# Get first user ID
USER_ID="$(curl -s -H "X-Emby-Token: $APIKEY" "$JellyfinURL/Users" | jq -r '.[0].Id')"

# Temp files
TMP_LIBS="$(mktemp)"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_LIBS" "$TMP_JSON"' EXIT INT TERM

# Get libraries as TSV: "Name<TAB>Id"
curl -s -H "X-Emby-Token: $APIKEY" "$JellyfinURL/Users/$USER_ID/Views"   | jq -r '.Items[] | "\(.Name)\t\(.Id)"' > "$TMP_LIBS"

if [ ! -s "$TMP_LIBS" ]; then
  echo "No Jellyfin libraries found for user $USER_ID." >&2
  exit 1
fi

# Numbered menu
echo "Select a Jellyfin library:"
awk -F'\t' '{printf "%2d) %s\n", NR, $1}' "$TMP_LIBS"

echo ""

printf "Enter number: "
IFS= read -r CHOICE

# Validate input
case "$CHOICE" in
  ''|*[!0-9]*) echo "Invalid selection." >&2; exit 1 ;;
esac
TOTAL=$(wc -l < "$TMP_LIBS" | tr -d ' ')
if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$TOTAL" ]; then
  echo "Selection out of range (1-$TOTAL)." >&2
  exit 1
fi

# Map number to ID + name
SEL_NAME=$(sed -n "${CHOICE}p" "$TMP_LIBS" | cut -f1)
LIB=$(sed -n "${CHOICE}p" "$TMP_LIBS" | cut -f2)
echo "Selected library: ${SEL_NAME:-unknown} ($LIB)" >&2

echo ""

# Ask search mode
echo "What would you like to search for?"
echo "  1) Unmatched items"
echo "  2) Duplicates"
echo "  3) Both"
printf "Enter 1, 2, or 3: "
IFS= read -r MODE

case "$MODE" in
  1) WANT_UNMATCHED=1; WANT_DUPLICATES=0 ;;
  2) WANT_UNMATCHED=0; WANT_DUPLICATES=1 ;;
  3) WANT_UNMATCHED=1; WANT_DUPLICATES=1 ;;
  *) echo "Invalid choice." >&2; exit 1 ;;
esac

echo "\n"
echo "Sometimes Jellyfin incorrectly outputs parent folders as Unmatched or Duplicates."
echo "You can exclude them if you want..."

# Ask whether to exclude folders from results
printf "Exclude folders from results? (y/N): "
IFS= read -r _ans_ex_folders
case "$_ans_ex_folders" in
  [Yy]|[Yy][Ee][Ss]) EXCLUDE_FOLDERS=1 ;;
  *) EXCLUDE_FOLDERS=0 ;;
esac

echo "\n"

# Ask about CSV output
printf "If you want to output to a CSV file, enter the filename here (press Enter to print to screen): "
IFS= read -r OUTFILE

echo "\n"

# Query once, include fields useful for duplicate detection
curl -s -H "X-Emby-Token: $APIKEY"   "$JellyfinURL/Users/$USER_ID/Items?ParentId=$LIB&Recursive=true&Fields=ProviderIds,Path,Type,ProductionYear,SeriesName,ParentIndexNumber,IndexNumber"   > "$TMP_JSON"


# Optionally exclude "Folder" items directly in the payload to keep subsequent logic unchanged
if [ "${EXCLUDE_FOLDERS:-0}" -eq 1 ]; then
  jq 'if has("Items") then .Items |= map(select(.Type != "Folder")) else . end' "$TMP_JSON" > "${TMP_JSON}.nofolder"
  mv "${TMP_JSON}.nofolder" "$TMP_JSON"
fi

# jq program (inlined below) computes 'Status' and filters by selected mode
if [ -n "$OUTFILE" ]; then
  # CSV with header: Type,Name,Path,ID,Status
  {
    echo "Type,Name,Path,ID,Status"
    jq -r --argjson want_unmatched "$WANT_UNMATCHED" --argjson want_duplicates "$WANT_DUPLICATES" '
      def dupkey:
        if .Type == "Movie" then ["Movie", (.Name//""), (.ProductionYear//"")]
        elif .Type == "Episode" then ["Episode", (.SeriesName//""), ((.ParentIndexNumber|tostring)//""), ((.IndexNumber|tostring)//"")]
        elif .Type == "Season" then ["Season", (.SeriesName//""), ((.IndexNumber|tostring)//"")]
        elif .Type == "Series" then ["Series", (.Name//"")]
        else [(.Type//""), (.Name//"")]
        end;
      .Items as $items
      | ($items | group_by(dupkey)
         | map(select(length > 1) | .[].Id)
         | reduce .[] as $id ({}; .[$id] = true)
        ) as $dup
      | $items[]
      | . as $it
      | (($it.ProviderIds == null) or (($it.ProviderIds | length) == 0)) as $is_unmatched
      | (($dup[$it.Id] // false) == true) as $is_duplicate
      | select( ( ($want_unmatched == 1) and $is_unmatched )
             or ( ($want_duplicates == 1) and $is_duplicate ) )
      | [ .Type, .Name, .Path, .Id,
          ( [ (if $is_unmatched then "Unmatched" else empty end),
              (if $is_duplicate then "Duplicate" else empty end) ] | join(";") )
        ]
      | @csv
    ' "$TMP_JSON"
  } > "$OUTFILE"
  echo "Wrote CSV to: $OUTFILE" >&2
  echo ""
else
  # Print to screen (TSV, same five columns)
  echo ""
  echo "Results:"
  echo "--------"
  echo ""
  jq -r --argjson want_unmatched "$WANT_UNMATCHED" --argjson want_duplicates "$WANT_DUPLICATES" '
    def dupkey:
      if .Type == "Movie" then ["Movie", (.Name//""), (.ProductionYear//"")]
      elif .Type == "Episode" then ["Episode", (.SeriesName//""), ((.ParentIndexNumber|tostring)//""), ((.IndexNumber|tostring)//"")]
      elif .Type == "Season" then ["Season", (.SeriesName//""), ((.IndexNumber|tostring)//"")]
      elif .Type == "Series" then ["Series", (.Name//"")]
      else [(.Type//""), (.Name//"")]
      end;
    .Items as $items
    | ($items | group_by(dupkey)
       | map(select(length > 1) | .[].Id)
       | reduce .[] as $id ({}; .[$id] = true)
      ) as $dup
    | $items[]
    | . as $it
    | (($it.ProviderIds == null) or (($it.ProviderIds | length) == 0)) as $is_unmatched
    | (($dup[$it.Id] // false) == true) as $is_duplicate
    | select( ( ($want_unmatched == 1) and $is_unmatched )
           or ( ($want_duplicates == 1) and $is_duplicate ) )
    | [ .Type, .Name, .Path, .Id,
        ( [ (if $is_unmatched then "Unmatched" else empty end),
            (if $is_duplicate then "Duplicate" else empty end) ] | join(";") )
      ]
    | @tsv
  ' "$TMP_JSON"
  echo ""
fi

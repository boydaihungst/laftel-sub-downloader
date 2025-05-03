#!/usr/bin/env bash

# Requirements: jq curl

FFMPEG_EXIST=true
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is not installed"
  FFMPEG_EXIST=false
fi

join_path() {
  if [[ "$OS" == "Windows_NT" ]]; then
    sep="\\"
  else
    sep="/"
  fi

  base="${1%[\\/]}" # Remove trailing "/" or "\"
  sub="${2#[\\/]}"  # Remove leading "/" or "\"

  echo "${base}${sep}${sub}"
}

is_valid_json() {
  echo "$1" | jq empty >/dev/null 2>&1
}

convert_vtt_to_srt() {
  if $FFMPEG_EXIST; then
    output_srt="$(echo "$1" | sed -E 's/\.vtt$/.srt/')"
    ffmpeg -y -nostdin -loglevel error -i "$1" "$output_srt"
    if [[ -f "$1" ]]; then
      rm "$1"
    fi
  fi
}

http_get() {
  curl -s "$1"
}

#######################################
# URL: https://api.laftel.tv/v1.0/series/search/?keyword=any_key_word&limit=25&offset=0
# Search series -> get series id
# Globals:
#   KEYWORD
#   LIMIT
#   PAGE
#   OFFSET
# Arguments:
#   1 - KEYWORD string
#   2 - LIMIT number
#   3 - PAGE number
#######################################
search_series() {
  QUERY="$1"
  if [[ -z "$QUERY" ]]; then
    echo "Error: --query is required for search action" >&2
    exit 1
  fi
  LIMIT=${2:-100}
  PAGE=${3:-0}
  OFFSET=$((PAGE * LIMIT))
  URL="https://api.laftel.tv/v1.0/series/search/?keyword=${QUERY}&limit=${LIMIT}&offset=${OFFSET}"
  data=$(http_get "$URL" | jq -r '.results[] | "\(.id): \(.title)"')

  # Format as table
  echo "$data" | awk -F': ' '
BEGIN {
    printf "%-10s | %-40s\n", "Series ID", "Title";
    print "-----------+----------------------------------------";
}
{
    printf "%-10s | %-40s\n", $1, $2;
}
'
}

#######################################
# Get list of recent updated series
# Globals:
#   LIMIT
#   OFFSET
# Arguments:
#   1 - LIMIT number
#   2 - PAGE number
#######################################
get_recent_updated_series() {
  LIMIT=${1:-100}
  PAGE=${2:-0}
  OFFSET=$((PAGE * LIMIT))
  URL="https://api.laftel.tv/v1.0/series/discover/?limit=${LIMIT}&offset=${OFFSET}&ordering=recent_updated"
  data=$(http_get "$URL" | jq -r '.results[] | "\(.id): \(.title)"')

  # Format as table
  echo "$data" | awk -F': ' '
BEGIN {
    printf "%-10s | %-40s\n", "Series ID", "Title";
    print "-----------+----------------------------------------";
}
{
    printf "%-10s | %-40s\n", $1, $2;
}
'
}

get_available_sub_lang() {
  SERIES_ID="${1}"
  SEASON_ID="${2}"
  URL="https://api.laftel.tv/v1.0/series/${SERIES_ID}/banner/?streaming_type=dash&season_id=${SEASON_ID}"
  response_banner_sub=$(http_get "$URL")
  if is_valid_json "$response_banner_sub"; then
    echo "$response_banner_sub" | jq -r '.highlight_video.subtitles[].language_code'
  else
    echo '[]' | jq .
  fi
}

get_sub_old_series() {
  SERIES_ID="${1}"
  SEASON_ID="${2}"
  LANGUAGE="${3}"
  URL="https://api.laftel.tv/v1.0/series/${SERIES_ID}/banner/?streaming_type=dash&season_id=${SEASON_ID}"
  response_banner=$(http_get "$URL")
  if is_valid_json "$response_banner_sub"; then
    if [[ -n "$LANGUAGE" ]]; then
      echo "$response_banner" | jq -r "[.highlight_video.subtitles[] | select(.language_code == \"${LANGUAGE}\")]"
    else
      echo "$response_banner" | jq -r ".highlight_video.subtitles"
    fi
  else
    echo '[]' | jq .
  fi
}

#######################################
# Get season id based on series id.
# Globals:
#   SERIES_ID
#   SEASON_NUM
# Arguments:
#   1 - SERIES_ID string|number
#   2 - SEASON_NUM string|number
#   3 - LAST_EPISODE_ONLY boolean (optional)
#######################################
get_seasons_id() {
  SERIES_ID=$1
  SEASON_NUM=$2
  LAST_EPISODE_ONLY=$3
  URL="https://api.laftel.tv/v1.0/seasons/?series_id=${SERIES_ID}"
  response_seasons=$(http_get "$URL")
  if is_valid_json "$response_banner_sub"; then

    if $LAST_EPISODE_ONLY; then
      echo "$response_seasons" | jq -c ". | max_by(.id)"
    elif [[ -n "$SEASON_NUM" ]]; then
      echo "$response_seasons" | jq -c ".[] | select(.index == \"${SEASON_NUM:-1}\")"
    else
      echo "$response_seasons" | jq -c ".[]"
    fi
  else
    echo '[]' | jq .
  fi

}

#######################################
# Get list of episodes based on season id.
# Globals:
#   SEASON_ID
#   OFFSET
#   LIMIT
# Arguments:
#   1 - SEASON_ID string|number
#   2 - PAGE number
#######################################
get_episodes() {
  OPTIONS=$(getopt -o s:p:l: --long seasonid:,page:,limit: -- "$@")
  eval set -- "$OPTIONS"

  PAGE=0
  LIMIT=1000
  while true; do
    case "$1" in
    -s | --seasonid)
      SERIES_ID="$2"
      shift 2
      ;;
    -p | --page)
      PAGE=$2
      shift 2
      ;;
    -l | --limit)
      LIMIT=$2
      shift 2
      ;;
    --)
      shift
      break
      ;; # End of options
    *) break ;;
    esac
  done

  OFFSET=$((PAGE * LIMIT))
  URL="https://api.laftel.tv/v1.0/episodes/?season_id=${SEASON_ID}&limit=${LIMIT}&offset=${OFFSET}"
  response=$(http_get "$URL")
  echo "$response"
}

download_sub() {
  OPTIONS=$(getopt -o i:s:o:l:n --long id:,season:,output:,lang:,newest -- "$@")
  eval set -- "$OPTIONS"

  OUTPUT=
  LAST_EPISODE_ONLY=false
  LANGUAGE=

  while true; do
    case "$1" in
    -i | --id)
      if [[ $2 -lt 0 ]]; then
        echo "Error: --id is required for download action" >&2
        exit 1
      fi
      SERIES_ID=$2
      shift 2
      ;;
    -s | --season)
      SEASON_NUM="$2"
      shift 2
      ;;
    -o | --output)
      if [[ -z "$2" ]] || [[ ! -d "$2" ]]; then
        echo "ERROR: OUTPUT should be a directory!"
        exit 1
      fi
      OUTPUT="$2"
      shift 2
      ;;
    -l | --lang)
      LANGUAGE="$2"
      shift 2
      ;;
    -n | --newest)
      LAST_EPISODE_ONLY=true
      shift 2
      ;;
    --)
      shift
      break
      ;; # End of options
    *) break ;;
    esac
  done

  while read -r season; do
    echo
    SEASON_ID=$(echo "$season" | jq -r '.id')
    SEASON_TITLE=$(echo "$season" | jq -r '.title')
    SEASON_NUM=$(echo "$season" | jq -r '.index')
    echo "Downloading subtitles for season $SEASON_NUM (id-$SEASON_ID): $SEASON_TITLE"
    unset last_ep_id
    unset last_sub_dl_url
    last_sub_id=-1

    mapfile -t available_langs < <(get_available_sub_lang "$SERIES_ID" "$SEASON_ID")
    # Ensure the array is not empty
    if [[ ${#available_langs[@]} -eq 0 ]]; then
      if ! $FORCE_LANGUAGE; then
        echo "No languages available. Force select any language with -f and -l arguments"
        continue
      else
        available_langs+=("$LANGUAGE")
        echo "Force selected $LANGUAGE language"
      fi
    else
      echo "Available languages: ${available_langs[@]}"
    fi
    if [[ -n "$LANGUAGE" ]]; then
      selected_valid_lang=false
      # Check if input_value exists in the valid_list
      for l in "${available_langs[@]}"; do
        if [[ "$LANGUAGE" == "$l" ]]; then
          selected_valid_lang=true
          break
        fi
      done
      if ! $selected_valid_lang; then
        echo "The selected subtitle language is not available"
        continue
      fi
    fi
    res_eps=$(get_episodes -s "$SEASON_ID" -l 1)
    latest_ep_idx=$(echo "$res_eps" | jq -r '.count')
    if $LAST_EPISODE_ONLY; then
      if ! (echo "$res_eps" | jq -e ".results[] | select(.index == \"${latest_ep_idx}\")" >/dev/null); then
        page=$((latest_ep_idx - 1))
        res_eps=$(get_episodes -s "$SEASON_ID" -l 1 -p $page)
      fi
    else
      if ! (echo "$res_eps" | jq -e ".results[] | select(.index == \"${latest_ep_idx}\")" >/dev/null); then
        page=$((latest_ep_idx - 1))
        res_eps=$(get_episodes -s "$SEASON_ID" -l "$latest_ep_idx")
      fi
    fi

    if [[ -n "$OUTPUT" ]]; then
      OUTPUT="$(join_path "$(pwd)" "$SEASON_TITLE")"
      mkdir -p "$OUTPUT"
    fi
    while read -r ep; do
      unset sub_dl_url
      ep_id=$(echo "$ep" | jq -r '.id')
      ep_fname="$(echo "$ep" | jq -r '.subtitle')"
      image_url="$(echo "$ep" | jq -r '.image')"
      case "$image_url" in
      *"/v1/"*[0-9a-fA-F]"/Preview."*)
        sub_dl_url=$(echo "$image_url" | sed -E 's|https://thumbnail\.laftel\.tv/assets/([0-9]+)/([0-9]+)/([0-9]+)/(\w+)/([a-zA-Z0-9]+)/Preview\.[0-9]+\.jpg|https://streaming.laftel.tv/\1/\2/\3/\4/\5/subtitles/|')
        if [[ -z "$sub_dl_url" ]]; then
          echo "Error downloading: $ep_fname"
          echo "URL not found"
          continue
        fi

        if [[ -z "$LANGUAGE" ]]; then
          for l in "${available_langs[@]}"; do
            dir_path="$(realpath "$(join_path "$OUTPUT" "$l")")"
            mkdir -p "$dir_path"
            curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt" "${sub_dl_url}${l}.vtt"
            convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt"
            echo "$ep_fname($l): 100%"
          done
        else
          dir_path="$(realpath "$(join_path "$OUTPUT" "$LANGUAGE")")"
          mkdir -p "$dir_path"
          curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt" "${sub_dl_url}${LANGUAGE}.vtt"
          convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt"
          echo "$ep_fname($LANGUAGE): 100%"
        fi
        ;;
      *"/v1/Preview."*)
        # "https://thumbnail.laftel.tv/assets/2024/01/4041/v1/Preview.0000057.jpg"
        # https://streaming.laftel.tv/2024/01/4041/v1/subtitles/
        sub_dl_url=$(echo "$image_url" | sed -E 's|https://thumbnail\.laftel\.tv/assets/([0-9]{4})/([0-9]{2})/([0-9]+)/v1/.*|https://streaming.laftel.tv/\1/\2/\3/v1/subtitles/|')
        if [[ -z "$sub_dl_url" ]]; then
          echo "Error downloading: $ep_fname"
          echo "URL not found"
          continue
        fi

        if [[ -z "$LANGUAGE" ]]; then
          for l in "${available_langs[@]}"; do
            dir_path="$(realpath "$(join_path "$OUTPUT" "$l")")"
            mkdir -p "$dir_path"
            curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt" "${sub_dl_url}${l}.vtt"
            convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt"
            echo "$ep_fname($l): 100%"
          done
        else
          dir_path="$(realpath "$(join_path "$OUTPUT" "$LANGUAGE")")"
          mkdir -p "$dir_path"
          curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt" "${sub_dl_url}${LANGUAGE}.vtt"
          convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt"
          echo "$ep_fname($LANGUAGE): 100%"
        fi
        ;;
      *)
        if [[ $last_sub_id -lt 0 ]]; then
          # https://streaming.laftel.tv/2024/01/5802/v1/087ec29ba2f5/highlights/21/subtitles/
          highlight_sub_ep_1_base_url="$(get_sub_old_series "$SERIES_ID" "$SEASON_ID" "$LANGUAGE" | jq -r '.[0].url' | sed -E 's#/subtitles/[a-zA-Z\-]+\.vtt$#/subtitles/#')"
          # https://streaming.laftel.tv/2024/01/5802/v1/subtitles/
          sub_dl_url="$(echo "$highlight_sub_ep_1_base_url" | sed -E 's#/v1/[a-f0-9]+/highlights/[0-9]+/#/v1/#')"
          # 5802
          sub_id=$(echo "$sub_dl_url" | sed -E 's#.*/[0-9]{4}/[0-9]{2}/([0-9]+)/.*#\1#')
        else
          sub_id=$(((ep_id - last_ep_id) + last_sub_id))
          sub_dl_url="$(echo "$last_sub_dl_url" | sed -E "s#(/[0-9]{4}/[0-9]{2}/)[0-9]+#\1${sub_id}#")"
        fi
        if [[ -z "$sub_dl_url" ]] || [[ -z "$sub_id" ]]; then
          echo "Error downloading: $ep_fname"
          echo "URL not found"
          continue
        fi

        if [[ -z "$LANGUAGE" ]]; then
          for l in "${available_langs[@]}"; do
            dir_path="$(realpath "$(join_path "$OUTPUT" "$l")")"
            mkdir -p "$dir_path"
            curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt" "${sub_dl_url}${l}.vtt"
            convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$l.vtt"
            echo "$ep_fname($l): 100%"
          done
        else
          dir_path="$(realpath "$(join_path "$OUTPUT" "$LANGUAGE")")"
          mkdir -p "$dir_path"
          curl -s -o "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt" "${sub_dl_url}${LANGUAGE}.vtt"
          convert_vtt_to_srt "$(join_path "$(realpath "$dir_path")" "$ep_fname").$LANGUAGE.vtt"
          echo "$ep_fname($LANGUAGE): 100%"
        fi
        last_ep_id=$ep_id
        last_sub_id=$sub_id
        last_sub_dl_url="$sub_dl_url"
        ;;
      esac
    done < <(echo "$res_eps" | jq -c '.results[]')
  done < <(get_seasons_id "$SERIES_ID" "$SEASON_NUM" $LAST_EPISODE_ONLY)
}

# Default values
ID=
SEASON=
OUTPUT="$(pwd)"
LANGUAGE=""
FORCE_LANGUAGE=false
NEWEST=false
ACTION=""
QUERY=""
LIMIT=25

# Usage function
usage() {
  echo "Usage: $0 [ACTION] [OPTIONS]"
  echo ""
  echo "Actions:"
  echo "  download                  Download subtitles"
  echo "  search                    Search series by name"
  echo "  recent                    Get recently updated series"
  echo ""
  echo "Options (download):"
  echo "  -i, --id ID               Set the Series ID (Required)"
  echo "  -s, --season SEASON       Set the season number"
  echo "  -o, --output DIRECTORY    Specify the output Directory"
  echo "  -l, --lang LANGUAGE       Set the language"
  echo "  -f, --force               Force to download even if available languages shows \"No languages available\""
  echo "  -n, --newest              Download only the latest episode"
  echo ""
  echo "Options (search):"
  echo "  -q, --query TEXT          Search query (Required)"
  echo ""
  echo "Options (recent):"
  echo "  -L, --limit NUMBER        Limit to NUMBER series (Required)"
  echo ""
  echo "Options:"
  echo "  -h, --help                Show this help message"
  echo ""
  exit 1
}

# Parse arguments using getopt
OPTIONS=$(getopt -o i:s:o:l:fnq:L:h --long id:,season:,output:,lang:,force,newest,query:,limit:,help -- "$@")
if [[ $? -ne 0 ]]; then
  echo "Error: Invalid options" >&2
  usage
fi

eval set -- "$OPTIONS"

# Ensure action is set
if [[ $# -lt 1 ]]; then
  echo "Error: Missing ACTION" >&2
  usage
fi

# Process options
while [[ $# -gt 0 ]]; do
  case "$1" in
  -i | --id)
    ID=$2
    shift 2
    ;;
  -s | --season)
    SEASON=$2
    shift 2
    ;;
  -o | --output)
    OUTPUT="$2"
    shift 2
    ;;
  -l | --lang)
    LANGUAGE="$2"
    shift 2
    ;;
  -f | --force)
    FORCE_LANGUAGE=true
    shift
    ;;
  -n | --newest)
    NEWEST=true
    shift
    ;;
  -q | --query)
    QUERY="$2"
    shift 2
    ;;
  -L | --limit)
    LIMIT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Error: Unexpected option $1" >&2
    usage
    ;;
  esac
done

ACTION="$1"
shift
# Execute the chosen action
case "$ACTION" in
download)
  if $NEWEST; then
    download_sub -i "$ID" -s "$SEASON" -o "$OUTPUT" -l "$LANGUAGE" -n
  else
    download_sub -i "$ID" -s "$SEASON" -o "$OUTPUT" -l "$LANGUAGE"
  fi
  ;;
search)
  search_series "$QUERY"
  ;;
"recent")
  get_recent_updated_series "$LIMIT"
  ;;
*)
  echo "Error: Unknown action '$ACTION'" >&2
  usage
  ;;
esac

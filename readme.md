# Laftel-downloader.sh

## Installation

`git clone https://github.com/boydaihungst/laftel-sub-downloader.git && cd laftel-sub-downloader`.
Requirements: curl, jq, sed, realpath, awk, getopt, eval, shift, pwd, mkdir.

Tested on linux.

## Usage

```bash
./laftel-sub-downloader.sh [ACTION] [OPTIONS]
```

```bash
  Usage: $0 [ACTION] [OPTIONS]

  Actions:
    download                  Download subtitles
    search                    Search series by name
    recent                    Get recently updated series

  Options (download):
    -i, --id ID               Set the Series ID (Required)
    -s, --season SEASON       Set the season number
    -o, --output DIRECTORY    Specify the output Directory
    -l, --lang LANGUAGE       Set the language
    -f, --force               Force to download even if available languages shows "No languages available"
    -n, --newest              Download only the latest episode

  Options (search):
    -q, --query TEXT          Search query (Required)

  Options (recent):
    -L, --limit NUMBER        Limit to NUMBER series (Required)

  Options:
    -h, --help                Show this help message

```

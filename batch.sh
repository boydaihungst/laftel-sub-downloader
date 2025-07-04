#!/bin/bash

# Get the directory where this script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to the input file
input_file="$script_dir/series.txt"

# Check if file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: File '$input_file' not found!"
  exit 1
fi

# Read entire file, split by whitespace (space, tab, newline)
while read -r line; do
  for number in $line; do
    echo "Downloading for number: $number"
    "$script_dir/laftel-downloader.sh" download -n -l vi -f -i "$number"
  done
done <"$input_file"

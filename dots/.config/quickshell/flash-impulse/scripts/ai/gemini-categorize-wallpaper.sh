#!/usr/bin/env bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <image_path> [model] [prompt]"
    echo "Tip: set GEMINI_WALLPAPER_MODEL and/or GEMINI_WALLPAPER_PROMPT to provide defaults."
    exit 1
fi

# Variables
SOURCE_IMG_PATH="$1"
# Same dead model as the translator had: gemini-2.5-flash 404s now. The lite
# variant is the fast one in the current roster.
MODEL="${2:-${GEMINI_WALLPAPER_MODEL:-gemini-3.5-flash-lite}}"
WALLPAPER_NAME="$(basename "$SOURCE_IMG_PATH")"
PROMPT="${3:-${GEMINI_WALLPAPER_PROMPT:-Categorize the wallpaper. Its file name is $WALLPAPER_NAME}}"
RESIZED_IMG_PATH="/tmp/quickshell/ai/wallpaper.jpg"

# Resize image for speed
mkdir -p "$(dirname "$RESIZED_IMG_PATH")"
magick "$SOURCE_IMG_PATH" -resize 200x -quality 50 "$RESIZED_IMG_PATH"

# Get API key
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_KEY=$("${SCRIPT_DIR}/../keyring/lookup.sh" 2> /dev/null | jq -r '.apiKeys.gemini // empty')
if [[ -z "$API_KEY" ]]; then
    echo "No Gemini API key in the keyring." >&2
    exit 1
fi

# Encode image to base64
if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
    B64FLAGS="--input"
else
    B64FLAGS="-w0"
fi
B64DATA="$(base64 $B64FLAGS $RESIZED_IMG_PATH)"
# echo $B64DATA

# Prepare request data
payload='{
    "contents": [{
        "parts":[
            {
                "inline_data": {
                "mime_type":"image/jpeg",
                "data": "'"$B64DATA"'"
                }
            },
            {"text": "'"$PROMPT"'"}
        ]
    }],
    "generationConfig": {
        "responseMimeType": "text/x.enum",
        "responseSchema": {
            "type": "string",
            "enum": [ "abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space" ]
        },
        "temperature": 0
    }
}'
# echo "$payload" | jq

# Make the request
response=$(curl "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
-H "x-goog-api-key: $API_KEY" \
-H 'Content-Type: application/json' \
-X POST \
-d "$payload" 2> /dev/null)
# echo "$response" | jq

# Write the result
echo "$response" | jq -r '.candidates[0].content.parts[0].text'

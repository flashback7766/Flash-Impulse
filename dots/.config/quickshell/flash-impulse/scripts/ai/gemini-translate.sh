#!/usr/bin/env bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <target_locale> [model]"
    exit 1
fi

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_CONFIG_DIR="$XDG_CONFIG_HOME/flash-impulse"
SHELL_CONFIG_FILE="${SHELL_CONFIG_DIR}/config.json"
TRANSLATIONS_DIR="${SCRIPT_DIR}/../../translations"
TRANSLATIONS_TARGET_DIR="${SHELL_CONFIG_DIR}/translations"
SOURCE_LOCALE="en_US"
NOTIFICATION_APP_NAME="Shell"
TARGET_LOCALE="$1"
# gemini-2.5-flash was the default here and it now 404s with "no longer
# available to new users" — which this script then wrote into the translation
# file as the string "null" and reported as success. Keep this in step with the
# roster in services/Ai.qml.
MODEL="${2:-${GEMINI_MODEL:-gemini-3.5-flash-lite}}"

# Update the source keys for translation
"${TRANSLATIONS_DIR}/tools/manage-translations.sh" update -l "$SOURCE_LOCALE" --yes
mkdir -p "$TRANSLATIONS_TARGET_DIR"

# Construct the prompt string.
#
# "Return the JSON object itself — not a string containing JSON" is doing real
# work here, not being polite. With responseMimeType set to application/json the
# model must answer with *some* JSON value, and asked less precisely it chose a
# JSON string holding the document, escaped — inconsistently, with keys escaped
# and values not, a few thousand keys in. Nothing downstream can parse that, and
# the old script wrote the resulting "null" straight over the translations.
# Fencing the input in ``` made it worse by suggesting another nesting level, so
# the content is passed plainly.
instruction='Translate the values of this JSON object into the locale '"$TARGET_LOCALE"'. Return the JSON object itself — not a string containing JSON, not markdown, not escaped. Keys must be copied byte-for-byte from the input; translate only the values. Be concise: this is a desktop shell UI and screen space is tight, and terminology should be apt (e.g. "discharging" is a battery state). Placeholders like %1 and newlines must be preserved exactly.'
content=$(cat "${TRANSLATIONS_DIR}/en_US.json")
source_keys=$(jq 'length' "${TRANSLATIONS_DIR}/en_US.json")
prompt_json=$(jq -n --arg prompt_text "$instruction" --arg content "$content" '$prompt_text + "\n\n" + $content')

# Prepare request data using jq
# --argjson, not --arg: prompt_json is already a JSON string value from the jq
# call above, and --arg would encode it a second time — shipping the model a
# blob full of \" instead of a prompt.
payload=$(jq -n \
    --argjson prompt "$prompt_json" \
    --arg temperature "0" \
    --arg model "$MODEL" \
    '{
        contents: [{
            parts: [
                {text: $prompt}
            ]
        }],
        generationConfig: {
            temperature: ($temperature | tonumber),
            "responseMimeType": "application/json",
        }
    }'
)
# echo "$payload" | jq

# Get API key. SCRIPT_DIR, not a bare dirname of $BASH_SOURCE: the shell invokes
# this by absolute path, but anything running it relative to another directory
# would otherwise look for the keyring helper in the wrong place.
API_KEY=$("${SCRIPT_DIR}/../keyring/lookup.sh" 2> /dev/null | jq -r '.apiKeys.gemini // empty')
if [[ -z "$API_KEY" ]]; then
    notify-send "Translation failed" "No Gemini API key stored. Open the left sidebar with Super+A and type /key." -a "$NOTIFICATION_APP_NAME"
    echo "No Gemini API key in the keyring." >&2
    exit 1
fi

# Notify start
notify-send "Translation started" "Will take 2 minutes, and you'll be notified when it's done, so feel free to do something else in the meantime." -a "$NOTIFICATION_APP_NAME"

# Make the request
response=$(curl "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
-H "x-goog-api-key: $API_KEY" \
-H 'Content-Type: application/json' \
-X POST \
-d "$payload" 2> /dev/null)
# echo "$response" | jq

# Check the response before touching anything. The previous version piped
# straight into the target file, so an API error wrote the literal string "null"
# over the translations, switched the interface to that locale, and still said
# "Translation complete" — leaving a shell with no visible text and no clue why.
api_error=$(printf '%s' "$response" | jq -r '.error.message // empty')
if [[ -n "$api_error" ]]; then
    notify-send "Translation failed" "$api_error" -a "$NOTIFICATION_APP_NAME"
    echo "Gemini API error: $api_error" >&2
    exit 1
fi

translated=$(printf '%s' "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

# Two shapes come back from the same request. Usually the part holds the JSON
# document directly. Sometimes — seen on gemini-3.5-flash-lite with this prompt —
# it holds the document *escaped*, i.e. the literal characters \n and \" rather
# than newlines and quotes, which is a JSON string body without its surrounding
# quotes. Wrapping it in quotes and decoding one level recovers the document.
# Accepting only the first shape is why a successful call still produced nothing.
if [[ -n "$translated" ]] && ! printf '%s' "$translated" | jq empty 2> /dev/null; then
    unescaped=$(printf '"%s"' "$translated" | jq -r . 2> /dev/null)
    if [[ -n "$unescaped" ]] && printf '%s' "$unescaped" | jq empty 2> /dev/null; then
        translated="$unescaped"
    fi
fi

# Anything still unparseable is a refusal, a truncation or a block — none of
# which belong in a translations file.
if [[ -z "$translated" ]] || ! printf '%s' "$translated" | jq empty 2> /dev/null; then
    reason=$(printf '%s' "$response" | jq -r '.candidates[0].finishReason // "no usable response"')
    notify-send "Translation failed" "Gemini returned nothing usable ($reason). Nothing was changed." -a "$NOTIFICATION_APP_NAME"
    echo "Unusable response ($reason)." >&2
    exit 1
fi

# A short answer is a truncated one. Overwriting a complete translation with a
# partial one loses work and is invisible until the missing strings show up in
# English, so require most of the keys to have come back.
got_keys=$(printf '%s' "$translated" | jq 'length')
if (( got_keys * 10 < source_keys * 9 )); then
    notify-send "Translation failed" "Only ${got_keys} of ${source_keys} strings came back. Nothing was changed." -a "$NOTIFICATION_APP_NAME"
    echo "Truncated response: ${got_keys}/${source_keys} keys." >&2
    exit 1
fi

# Write the result
printf '%s\n' "$translated" > "${TRANSLATIONS_TARGET_DIR}/${TARGET_LOCALE}.json"
jq --arg locale "$TARGET_LOCALE" '.language.ui = $locale' "$SHELL_CONFIG_FILE" > "${SHELL_CONFIG_FILE}.tmp" && mv "${SHELL_CONFIG_FILE}.tmp" "$SHELL_CONFIG_FILE"
notify-send "Translation complete" "Enjoy! In case you wanna refine it, the file is in ${TRANSLATIONS_TARGET_DIR}/${TARGET_LOCALE}.json" -a "$NOTIFICATION_APP_NAME"

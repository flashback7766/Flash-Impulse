#!/usr/bin/env bash

# Translates the shell's strings into a locale with Gemini, under the free
# tier's limits. The whole file in one request never worked: 1350 keys come
# back truncated, and the truncation guard threw the whole run away. Now the
# work is chunked, merged into the target as it goes, and a re-run continues
# where the last one stopped — free-tier quotas and flaky networks included.

if [[ -z "$1" ]]; then
    echo "Usage: $0 <target_locale> [model]"
    exit 1
fi

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_CONFIG_DIR="${XDG_CONFIG_HOME}/flash-impulse"
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

# Free-tier pacing: flash-lite allows roughly 15 requests a minute, so a
# little over four seconds between requests stays under it without dragging
# the whole run out. Both are overridable for a paid key or a stricter cap.
CHUNK="${TRANSLATE_CHUNK:-100}"
RPM_SLEEP="${TRANSLATE_RPM_SLEEP:-4.5}"
MAX_RETRIES=5

# Update the source keys for translation
"${TRANSLATIONS_DIR}/tools/manage-translations.sh" update -l "$SOURCE_LOCALE" --yes
mkdir -p "$TRANSLATIONS_TARGET_DIR"
TARGET_FILE="${TRANSLATIONS_TARGET_DIR}/${TARGET_LOCALE}.json"

# Get API key. SCRIPT_DIR, not a bare dirname of $BASH_SOURCE: the shell invokes
# this by absolute path, but anything running it relative to another directory
# would otherwise look for the keyring helper in the wrong place.
API_KEY=$("${SCRIPT_DIR}/../keyring/lookup.sh" 2> /dev/null | jq -r '.apiKeys.gemini // empty')
if [[ -z "$API_KEY" ]]; then
    notify-send "Translation failed" "No Gemini API key stored. Open the left sidebar with Super+A and type /key." -a "$NOTIFICATION_APP_NAME"
    echo "No Gemini API key in the keyring." >&2
    exit 1
fi

translate_batch() {
    # $1 = JSON object of keys to translate. Prints the translated object on
    # stdout; nothing on stdout when the batch could not be translated.
    local batch="$1" attempt response api_error translated unescaped retry_after
    local instruction='Translate the values of this JSON object into the locale '"$TARGET_LOCALE"'. Return the JSON object itself — not a string containing JSON, not markdown, not escaped. Keys must be copied byte-for-byte from the input; translate only the values. Be concise: this is a desktop shell UI and screen space is tight, and terminology should be apt (e.g. "discharging" is a battery state). Placeholders like %1 and newlines must be preserved exactly.'

    local prompt_json payload
    prompt_json=$(jq -n --arg prompt_text "$instruction" --arg content "$batch" '$prompt_text + "\n\n" + $content')
    # --argjson, not --arg: prompt_json is already a JSON string value from the jq
    # call above, and --arg would encode it a second time — shipping the model a
    # blob full of \" instead of a prompt.
    payload=$(jq -n \
        --argjson prompt "$prompt_json" \
        --arg temperature "0" \
        '{
            contents: [{
                parts: [
                    {text: $prompt}
                ]
            }],
            generationConfig: {
                temperature: ($temperature | tonumber),
                "responseMimeType": "application/json"
            }
        }'
    )

    for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
        response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
            -H "x-goog-api-key: $API_KEY" \
            -H 'Content-Type: application/json' \
            -X POST \
            -d "$payload" 2> /dev/null)

        # A rate limit is a "wait and try again", not a failure: the free tier
        # hands out its own retry delay and it is worth obeying.
        api_error=$(printf '%s' "$response" | jq -r '.error.message // empty')
        if printf '%s' "$response" | jq -e '.error.status == "RESOURCE_EXHAUSTED" or .error.code == 429' > /dev/null 2>&1; then
            retry_after=$(printf '%s' "$response" | jq -r '.error.details[]? | select(.["@type"] // "" | endswith("RetryInfo")) | .retryDelay // empty' | tr -d 's')
            retry_after=${retry_after:-30}
            echo "Rate limited; waiting ${retry_after}s (attempt ${attempt}/${MAX_RETRIES})." >&2
            sleep "$retry_after"
            continue
        fi
        if [[ -n "$api_error" ]]; then
            echo "Gemini API error: $api_error" >&2
            return 1
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

        # Anything still unparseable is a refusal, a truncation or a block.
        if [[ -z "$translated" ]] || ! printf '%s' "$translated" | jq -e 'type == "object"' > /dev/null 2>&1; then
            local reason
            reason=$(printf '%s' "$response" | jq -r '.candidates[0].finishReason // "no usable response"')
            echo "Unusable response (${reason}), attempt ${attempt}/${MAX_RETRIES}." >&2
            sleep 2
            continue
        fi

        printf '%s' "$translated"
        return 0
    done
    return 1
}

notify-send "Translation started" "${TARGET_LOCALE}: translating in chunks of ${CHUNK} strings. You'll be notified when it's done." -a "$NOTIFICATION_APP_NAME"

# The target file doubles as the resume state: whatever a previous run
# translated is kept, and only the keys still missing go to the model.
existing="{}"
if [[ -f "$TARGET_FILE" ]]; then
    existing=$(cat "$TARGET_FILE")
fi

source_keys=$(jq 'length' "${TRANSLATIONS_DIR}/${SOURCE_LOCALE}.json")
source_json=$(cat "${TRANSLATIONS_DIR}/${SOURCE_LOCALE}.json")
total=$(jq -r 'keys | length' <<< "$source_json")
done_keys=$(jq 'length' <<< "$existing")

offset=0
while (( offset < total )); do
    batch=$(jq -c --argjson off "$offset" --argjson n "$CHUNK" 'to_entries[$off:($off + $n)] | from_entries' <<< "$source_json")
    batch_count=$(jq 'length' <<< "$batch")

    # Skip the keys a previous run already translated — this is what makes a
    # re-run a continuation instead of a repeat.
    # The merged file outgrew --argjson fast: Linux caps a single argument at
    # 128KB, and a thousand translated strings blow past it (E2BIG, silently
    # empty). The resume state travels by file instead.
    existing_file=$(mktemp)
    printf '%s' "$existing" > "$existing_file"
    batch=$(jq -c --argjson b "$batch" --slurpfile e "$existing_file" '$b | with_entries(select(.key as $k | ($e[0] | has($k)) | not))' <<< "$batch")
    rm -f "$existing_file"
    remaining=$(jq 'length' <<< "$batch")

    if (( remaining == 0 )); then
        offset=$((offset + batch_count))
        continue
    fi
    echo "Translating ${remaining} strings (offset ${offset})..."

    if ! translated=$(translate_batch "$batch"); then
        notify-send "Translation paused" "A chunk failed; progress is kept (${done_keys}/${total}). Run again to continue." -a "$NOTIFICATION_APP_NAME"
        echo "Chunk failed; the target file holds what was translated so far." >&2
        exit 1
    fi

    got=$(jq 'length' <<< "$translated")
    if (( got * 10 < remaining * 9 )); then
        notify-send "Translation paused" "Only ${got} of ${remaining} strings came back; progress is kept (${done_keys}/${total}). Run again to continue." -a "$NOTIFICATION_APP_NAME"
        echo "Short chunk: ${got}/${remaining}." >&2
        exit 1
    fi

    existing=$(jq -c -s '.[0] * .[1]' <<< "$existing $translated")
    # Atomic write: a crash mid-run leaves a complete file of what translated.
    printf '%s\n' "$existing" | jq . > "${TARGET_FILE}.tmp" && mv "${TARGET_FILE}.tmp" "$TARGET_FILE"
    done_keys=$(jq 'length' <<< "$existing")
    echo "Progress: ${done_keys}/${total}."

    offset=$((offset + batch_count))
    if (( offset < total )); then
        sleep "$RPM_SLEEP"
    fi
done

final_keys=$(jq 'length' "$TARGET_FILE")
jq --arg locale "$TARGET_LOCALE" '.language.ui = $locale' "$SHELL_CONFIG_FILE" > "${SHELL_CONFIG_FILE}.tmp" && mv "${SHELL_CONFIG_FILE}.tmp" "$SHELL_CONFIG_FILE"
notify-send "Translation complete" "${TARGET_LOCALE}: ${final_keys}/${source_keys} strings. The interface language is switched." -a "$NOTIFICATION_APP_NAME"
echo "Done: ${final_keys}/${source_keys} strings in ${TARGET_FILE}."

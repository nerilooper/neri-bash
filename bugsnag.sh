
# Open the Bugsnag dashboard with a specific time range.
# Usage: bugsnag_open <start_date> <relative_end / end_date>
# Example: bugsnag_open 2020-01-01T00:00:00.000Z 1d
alias bugsnag_open='function() {
    local base_url="https://app.bugsnag.com/doorloop/doorloop/errors?filters[event.since]=";
    local start_date="$1";
    local relative_end="$2";
    local end_date="";

    start_date=$(echo "$start_date" | sed -E "s/\.[0-9]+Z$/Z/");

    if [[ "$relative_end" =~ ^[0-9]+[dh]$ ]]; then
        local unit="${relative_end: -1}";
        local value="${relative_end%${unit}}";

        if [[ "$unit" == "d" ]]; then
            end_date=$(date -u -v+${value}d -j -f "%Y-%m-%dT%H:%M:%SZ" "${start_date}" +"%Y-%m-%dT%H:%M:%SZ");
        elif [[ "$unit" == "h" ]]; then
            end_date=$(date -u -v+${value}H -j -f "%Y-%m-%dT%H:%M:%SZ" "${start_date}" +"%Y-%m-%dT%H:%M:%SZ");
        fi
    else
        echo "Invalid relative end time format. Use something like '1d' or '6h'."
        return 1;
    fi

    local full_url="${base_url}${start_date}";
    if [[ -n "$end_date" ]]; then
        full_url="${full_url}&filters[event.before]=${end_date}";
    fi;

    echo "Opening URL: $full_url"

    open "$full_url";
}'
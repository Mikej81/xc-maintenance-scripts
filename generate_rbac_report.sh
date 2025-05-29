#!/bin/bash

# Input validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <api_key> <tenant_name>"
    exit 1
fi

API_KEY="$1"
TENANT_NAME="$2"
BASE_URL="https://${TENANT_NAME}.console.ves.volterra.io"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Temp files
ROLES_FILE=$(mktemp)
GROUP_DETAIL=$(mktemp)
ELEMENT_DETAIL=$(mktemp)

# Fetch all roles
curl -s -H "Authorization: APIToken ${API_KEY}" \
  "$BASE_URL/api/web/custom/namespaces/system/roles" > "$ROLES_FILE"

# Initialize counters
PAGE=1
COUNT=0
MAX_PER_PAGE=20
REPORT_FILE="rbac_table_report_${TENANT_NAME}_page${PAGE}.md"

# Start first page
echo "# F5 XC User Role Audit Report" > "$REPORT_FILE"
echo "_Page ${PAGE}_  " >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Loop through each role
jq -c '.items[]' "$ROLES_FILE" | while read -r role; do
    # Paginate
    if [ "$COUNT" -ge "$MAX_PER_PAGE" ]; then
        PAGE=$((PAGE + 1))
        COUNT=0
        REPORT_FILE="rbac_table_report_${TENANT_NAME}_page${PAGE}.md"
        echo "# F5 XC User Role Audit Report" > "$REPORT_FILE"
        echo "_Page ${PAGE}_  " >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    COUNT=$((COUNT + 1))

    # Parse role metadata
    ROLE_NAME=$(echo "$role" | jq -r '.name')
    TENANT=$(echo "$role" | jq -r '.tenant')
    NAMESPACE=$(echo "$role" | jq -r '.namespace')
    COMBINED_NS="${TENANT}-${NAMESPACE}"

    echo "## Role: \`$ROLE_NAME\` ($TENANT/$NAMESPACE)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| API Group | Element | Method(s) | Path Regex |" >> "$REPORT_FILE"
    echo "|-----------|---------|-----------|-------------|" >> "$REPORT_FILE"

    # For each API group
    echo "$role" | jq -r '.api_groups[]?' | while read -r API_GROUP; do
        API_GROUP_URL="${BASE_URL}/api/web/namespaces/${COMBINED_NS}/api_groups/${API_GROUP}"
        curl -s -H "Authorization: APIToken ${API_KEY}" "$API_GROUP_URL" > "$GROUP_DETAIL"

        if jq -e '.spec.elements' "$GROUP_DETAIL" &>/dev/null; then
            element_count=$(jq '.spec.elements | length' "$GROUP_DETAIL")
            row_index=0

            jq -c '.spec.elements[]' "$GROUP_DETAIL" | while read -r element; do
                ELEMENT_NAME=$(echo "$element" | jq -r '.name')
                ELEMENT_URL="${BASE_URL}/api/web/namespaces/${COMBINED_NS}/api_group_elements/${ELEMENT_NAME}"

                curl -s -H "Authorization: APIToken ${API_KEY}" "$ELEMENT_URL" > "$ELEMENT_DETAIL"

                METHODS=$(jq -r '.spec.methods | join(", ") // "N/A"' "$ELEMENT_DETAIL")
                PATH_REGEX=$(jq -r '.spec.path_regex // "N/A"' "$ELEMENT_DETAIL")

                if [ "$row_index" -eq 0 ]; then
                    echo "| \`$API_GROUP\` | \`$ELEMENT_NAME\` | $METHODS | \`$PATH_REGEX\` |" >> "$REPORT_FILE"
                else
                    echo "|             | \`$ELEMENT_NAME\` | $METHODS | \`$PATH_REGEX\` |" >> "$REPORT_FILE"
                fi
                row_index=$((row_index + 1))
            done
        else
            echo "| \`$API_GROUP\` | N/A | N/A | N/A |" >> "$REPORT_FILE"
        fi
    done

    echo "" >> "$REPORT_FILE"
done

# Cleanup
rm "$ROLES_FILE" "$GROUP_DETAIL" "$ELEMENT_DETAIL"

echo "Markdown RBAC report generated in pages: rbac_table_report_${TENANT_NAME}_page*.md"

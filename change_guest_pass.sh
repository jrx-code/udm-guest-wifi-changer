#!/bin/bash

# Configuration
SECRETS_FILE="/config/secrets.yaml"
LOG_FILE="/config/scripts/change_guest_wifi.log"
SITE_ID="default"  # Fixed site ID

# Function definitions
log_error() {
    echo "[ERROR] $(date): $1" | tee -a "$LOG_FILE"
    exit 1
}

log_info() {
    echo "[INFO] $(date): $1" | tee -a "$LOG_FILE"
}

log_mock() {
    echo "[SIMULATION] $(date): $1" | tee -a "$LOG_FILE"
}

# Read secrets (all required, no fallbacks)
read_secrets() {
    if [ ! -f "$SECRETS_FILE" ]; then
        log_error "Missing secrets.yaml: $SECRETS_FILE (udm_api_key, ha_url, ha_llat_token, guest_lan required)"
    fi

    # Read UDM_HOST (required)
    UDM_HOST=$(grep "^ *udm_host: *" "$SECRETS_FILE" | sed 's/.*udm_host: *\(.*\)/\1/' | sed 's/^"\|"$//g' | xargs)
    if [ -z "$UDM_HOST" ]; then
        log_error "Missing required udm_host in $SECRETS_FILE (UDM Pro IP or hostname)"
    else
        log_info "UDM Host: $UDM_HOST"
    fi

    # Read UDM API Key (required)
    API_KEY=$(grep "^ *udm_api_key: *" "$SECRETS_FILE" | sed 's/.*udm_api_key: *\(.*\)/\1/' | sed 's/^"\|"$//g' | xargs)
    if [ -z "$API_KEY" ]; then
        log_error "Missing required udm_api_key in $SECRETS_FILE (from UDM > Settings > Control Plane > Integrations > New Key)"
    fi

    # Read HA URL (required)
    HA_URL=$(grep "^ *ha_url: *" "$SECRETS_FILE" | sed 's/.*ha_url: *\(.*\)/\1/' | sed 's/^"\|"$//g' | xargs)
    if [ -z "$HA_URL" ]; then
        log_error "Missing required ha_url in $SECRETS_FILE (Home Assistant URL or hostname)"
    else
        log_info "HA URL: $HA_URL"
    fi

    # Read HA Long-Lived Access Token (required)
    HA_TOKEN=$(grep "^ *ha_llat_token: *" "$SECRETS_FILE" | sed 's/.*ha_llat_token: *\(.*\)/\1/' | sed 's/^"\|"$//g' | xargs)
    if [ -z "$HA_TOKEN" ]; then
        log_error "Missing required ha_llat_token in $SECRETS_FILE (from HA > Profile > Long-Lived Access Tokens)"
    fi

    # Read Guest SSID Name (required)
    SSID_NAME=$(grep "^ *guest_lan: *" "$SECRETS_FILE" | sed 's/.*guest_lan: *\(.*\)/\1/' | sed 's/^"\|"$//g' | xargs)
    if [ -z "$SSID_NAME" ]; then
        log_error "Missing required guest_lan in $SECRETS_FILE (exact WiFi SSID name to change)"
    else
        log_info "Target SSID: $SSID_NAME"
    fi

    log_info "All secrets loaded from $SECRETS_FILE (X-API-Key authentication for UDM, Bearer token for HA, site=default)"
}

# Password generator (BusyBox compatible, 16 chars with required types)
generate_password() {
    local length=16
    local charset="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?"

    # Generate one character from each required type
    local lower=$(tr -dc "abcdefghijklmnopqrstuvwxyz" < /dev/urandom | head -c1)
    local upper=$(tr -dc "ABCDEFGHIJKLMNOPQRSTUVWXYZ" < /dev/urandom | head -c1)
    local digit=$(tr -dc "0123456789" < /dev/urandom | head -c1)
    local special=$(tr -dc "!@#$%^&*()_+-=[]{}|;:,.<>?" < /dev/urandom | head -c1)

    # Generate remaining 12 random characters from full charset
    local rest=$(tr -dc "$charset" < /dev/urandom | head -c12)

    # Concatenate all parts (16 characters total)
    echo -n "$lower$upper$digit$special$rest"
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [-t|--test] [-h|--help] [PASSWORD]

Change the guest WiFi password on the UDM Pro and update Home Assistant.

  -t, --test   Simulate only (dry-run), no changes on UDM or in HA
  -h, --help   Show this help and exit
  PASSWORD     Custom password (default: random 16-character password)

Configuration is read from $SECRETS_FILE.
USAGE
}

# Main execution
TEST_MODE=false
NEW_PASSWORD=""

# Parse command line flags and arguments (before reading secrets, so -h works without them)
for arg in "$@"; do
    case $arg in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--test)
            TEST_MODE=true
            ;;
        *)
            NEW_PASSWORD="$arg"  # Use first non-flag argument as custom password
            ;;
    esac
done

read_secrets

# Generate random password if no custom password provided
if [ -z "$NEW_PASSWORD" ]; then
    NEW_PASSWORD=$(generate_password)
    log_info "Generated random password (16 characters): '$NEW_PASSWORD'"
fi

# Validate password length (UniFi requires exactly 16 chars for WPA2/3)
if [ ${#NEW_PASSWORD} -ne 16 ]; then
    log_error "Password must be exactly 16 characters (current: ${#NEW_PASSWORD}). Generated: '$NEW_PASSWORD'"
fi

log_info "Execution mode: $( [ "$TEST_MODE" = true ] && echo "TEST (dry-run simulation)" || echo "REAL (apply changes)" )"
log_info "Password: '$NEW_PASSWORD' | Target SSID: '$SSID_NAME' | UDM Host: '$UDM_HOST' | Site: '$SITE_ID'"

# Fetch WLAN configuration list from UDM Pro using X-API-Key
log_info "Fetching WLAN list from $UDM_HOST: https://$UDM_HOST/proxy/network/api/s/$SITE_ID/rest/wlanconf"
WLAN_RESPONSE=$(curl -k -s -w "%{http_code}" \
    -X GET \
    -H "X-API-KEY: $API_KEY" \
    "https://$UDM_HOST/proxy/network/api/s/$SITE_ID/rest/wlanconf")

HTTP_CODE=${WLAN_RESPONSE: -3}
WLAN_BODY=${WLAN_RESPONSE%???}

if [ "$HTTP_CODE" -ne 200 ]; then
    log_info "WLAN GET error (code: $HTTP_CODE). Response body: $WLAN_BODY"
    case $HTTP_CODE in
        401)
            log_error "401 Unauthorized: Invalid udm_api_key. Regenerate in UDM > Settings > Control Plane > Integrations > New Key (owner/full access required)"
            ;;
        403)
            log_error "403 Forbidden: API key lacks required permissions for site '$SITE_ID'. Ensure full Network access in Integrations"
            ;;
        404)
            log_error "404 Not Found: Endpoint https://$UDM_HOST/proxy/network/api/s/$SITE_ID/rest/wlanconf not found. Verify UDM host and site configuration"
            ;;
        *)
            log_error "UDM API GET error: HTTP $HTTP_CODE. Check UDM host ($UDM_HOST) accessibility"
            ;;
    esac
fi

# Search for SSID_ID matching the target SSID name
log_info "Searching for SSID_ID matching '$SSID_NAME' in WLAN response..."
SSID_ID=$(echo "$WLAN_BODY" | sed -n "s/.*\"name\":\"$SSID_NAME\".*\"_id\":\"\([^\"]*\)\".*/\1/p" | head -1)

if [ -z "$SSID_ID" ]; then
    # List all available SSIDs for debugging
    AVAILABLE_SSIDS=$(echo "$WLAN_BODY" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ')
    log_error "Target SSID '$SSID_NAME' not found in UDM configuration.\nAvailable SSIDs: $AVAILABLE_SSIDS\nCheck UDM > Settings > WiFi > Networks (ensure guest network exists with exact name)"
fi

log_info "Found matching SSID. ID: '$SSID_ID' | Name: '$SSID_NAME'"

# Change WLAN password (skip in test mode)
if [ "$TEST_MODE" = true ]; then
    log_mock "SIMULATION: Would execute PUT to UDM using X-API-KEY header"
    log_mock "SIMULATION: URL: https://$UDM_HOST/proxy/network/api/s/$SITE_ID/rest/wlanconf/$SSID_ID"
    log_mock "SIMULATION: Body: {\"_id\": \"$SSID_ID\", \"x_passphrase\": \"$NEW_PASSWORD\"}"
    log_mock "SIMULATION: New password '$NEW_PASSWORD' would be applied to SSID '$SSID_NAME'"
    log_mock "SIMULATION: Access Points would receive updated configuration within 1-2 minutes"
else
    log_info "Executing PUT to UDM: changing password for WLAN ID '$SSID_ID' using X-API-KEY"
    PUT_RESPONSE=$(curl -k -s -w "%{http_code}" \
        -X PUT \
        -H "X-API-KEY: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_id\": \"$SSID_ID\", \"x_passphrase\": \"$NEW_PASSWORD\"}" \
        "https://$UDM_HOST/proxy/network/api/s/$SITE_ID/rest/wlanconf/$SSID_ID")

    PUT_CODE=${PUT_RESPONSE: -3}

    if [ "$PUT_CODE" -ne 200 ]; then
        log_info "PUT error (code: $PUT_CODE). Response body: ${PUT_RESPONSE%???}"
        case $PUT_CODE in
            400)
                log_error "400 Bad Request: Invalid JSON format or x_passphrase field. Password length verified: ${#NEW_PASSWORD} characters"
                ;;
            401)
                log_error "401 Unauthorized: Invalid API key (udm_api_key). Regenerate in UDM Integrations with owner/full access"
                ;;
            403)
                log_error "403 Forbidden: API key lacks PUT permissions for WLAN configuration. Verify full Network access in Integrations"
                ;;
            404)
                log_error "404 Not Found: WLAN ID '$SSID_ID' does not exist. Verify SSID configuration in UDM"
                ;;
            500)
                log_error "500 Internal Server Error: UDM Pro server issue. Try restarting Network application in UniFi OS"
                ;;
            *)
                log_error "UDM API PUT error: HTTP $PUT_CODE"
                ;;
        esac
    fi

    log_info "WiFi password updated successfully on UDM Pro (HTTP: $PUT_CODE) using X-API-KEY"
    log_info "Access Points will automatically reprovision with new configuration within 1-2 minutes"
fi

# Update Home Assistant entity (skip in test mode)
if [ "$TEST_MODE" = false ]; then
    log_info "Updating HA entity using Bearer token authentication"
    HA_RESPONSE=$(curl -k -s -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"state\": \"$NEW_PASSWORD\"}" \
        "https://$HA_URL:8123/api/states/input_text.guest_wifi_password")

    HA_CODE=${HA_RESPONSE: -3}

    if [ "$HA_CODE" -ne 200 ]; then
        log_info "HA update warning (code: $HA_CODE). Response body: ${HA_RESPONSE%???}"
        case $HA_CODE in
            401)
                log_error "401 HA Unauthorized: Invalid ha_llat_token. Regenerate in HA > Profile > Long-Lived Access Tokens"
                ;;
            404)
                log_error "404 HA Not Found: Entity input_text.guest_wifi_password does not exist. Create via Helpers > Text in HA"
                ;;
            *)
                log_error "HA API update error: HTTP $HA_CODE"
                ;;
        esac
    else
        log_info "HA entity state updated successfully (HTTP: $HA_CODE) using Bearer token with password '$NEW_PASSWORD'"
    fi
else
    log_mock "SIMULATION: Would update HA entity using Bearer token authentication"
    log_mock "SIMULATION: URL: https://$HA_URL:8123/api/states/input_text.guest_wifi_password"
    log_mock "SIMULATION: Header: Authorization: Bearer [TOKEN]"
    log_mock "SIMULATION: Body: {\"state\": \"$NEW_PASSWORD\"}"
    log_mock "SIMULATION: Entity input_text.guest_wifi_password state would be set to '$NEW_PASSWORD' (skipped)"
fi

log_info "Script execution completed $( [ "$TEST_MODE" = true ] && echo "(simulation mode - no changes applied)" || echo "(changes applied successfully)" )"


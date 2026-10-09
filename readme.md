# UDM Pro Guest WiFi Password Changer

Automated script to change guest WiFi password on Ubiquiti UDM Pro and update Home Assistant entity. Integrates with UDM Pro API (X-API-Key) and Home Assistant REST API (Bearer token). Generates secure 16-character passwords and supports test mode for dry-run simulation.

## Features

- **Secure Password Generation**: Creates 16-character passwords with lowercase, uppercase, digits, and special characters (UniFi WPA2/3 compliant).
- **UDM Pro Integration**: Changes WiFi password via UniFi Network API (site=default).
- **Home Assistant Sync**: Updates `input_text.guest_wifi_password` entity state automatically.
- **Test Mode**: Simulates changes without applying them (dry-run).
- **Robust Secrets Management**: Reads configuration from YAML file (no environment variables or fallbacks).
- **Comprehensive Logging**: Detailed logs with timestamps for debugging and monitoring.
- **Error Handling**: Specific error messages for API failures, missing secrets, invalid SSID, etc.
- **BusyBox Compatible**: Works in container environments (e.g., Home Assistant add-on, Docker).

## Requirements

### Homeassistan
- ** QR-Code-Generator** integration for autogeneration of qr codes: https://github.com/DeerMaximum/QR-Code-Generator, simple config: name - anything, Content: 
``` WIFI:T:WPA2;S:your-wifi-name-here;P:{{states("your-entity-storing-password")}};H:true;```

- **Example: **
``` 
    Name: Guest-Wifi
    Content: WIFI:T:WPA2;S:My-Super-Guest-Wifi;P:{{states("input_text.guest_wifi_password")}};H:true;
```

### Hardware/Software
- **UDM Pro** (UniFi Dream Machine Pro) with Network application running.
- **Home Assistant** (Core/Add-on/Supervised) with REST API enabled.
- **Linux/Unix Shell** (tested on Debian/Raspberry Pi OS, BusyBox).

### Configuration
- **UDM Pro API Key**: Generated from UDM > Settings > Control Plane > Integrations > New Key.
- **Home Assistant Long-Lived Access Token**: From HA > Profile > Long-Lived Access Tokens (full API scope).
- **Guest WiFi SSID**: Exact name from UDM > Settings > WiFi > Networks (case-sensitive).
- **HA Entity**: Create `input_text.guest_wifi_password` via Helpers > Text (or automation).

### Dependencies
- `curl` (for API requests).
- `sed`, `awk`, `grep`, `tr`, `head` (standard Unix tools).
- `/dev/urandom` (for password generation).

## Installation

1. **Clone Repository**:
   ```bash
   git clone https://github.com/yourusername/udm-guest-wifi-changer.git
   cd udm-guest-wifi-changer
   ```

2. **Create Secrets File** (`/config/secrets.yaml` for HA add-on, or `./secrets.yaml`):
   ```yaml
   udm_host: your-udm-ip or hostname  # UDM Pro IP or hostname
   udm_api_key: your_udm_api_token_here  # From UDM Integrations
   ha_url: homeassistant.home.lan  # HA hostname (no http:// or port)
   ha_llat_token: your_ha_long_lived_access_token_here  # From HA Profile
   guest_lan: your-guest-network-name  # Exact guest SSID name from UDM
   ```

3. **Make Script Executable**:
   ```bash
   chmod +x change_guest_pass.sh
   ```

4. **For Home Assistant Add-on/Integration**:
   - Place script in `/config/scripts/`.
   - Add to HA automation or shell command: `shell_command.guest_wifi_change: /config/scripts/change_guest_pass.sh "{{ password|default('') }}"`.
   - Trigger via automation (e.g., monthly cron) or button card.

## Usage

### Basic Commands

```bash
# Show help
./change_guest_pass.sh -h

# Test mode (simulate without changes)
./change_guest_pass.sh --test
# Or short form
./change_guest_pass.sh -t

# Real change with random password
./change_guest_pass.sh

# Real change with custom 16-char password
./change_guest_pass.sh "MySecure16CharPassword123!"

# Test with custom password
./change_guest_pass.sh -t "MySecure16CharPassword123!"
```

### Expected Output

**Test Mode**:
```
[INFO] Tue Nov 18 20:51:00 CET 2025: UDM Host: 192.168.1.1
[INFO] ... All secrets loaded from /config/secrets.yaml
[INFO] ... Generated random password (16 characters): 'aB3!xYz9pQ2wEr5t'
[INFO] ... Execution mode: TEST (dry-run simulation)
[SIMULATION] ... Would execute PUT to UDM using X-API-KEY header
[SIMULATION] ... New password 'aB3!xYz9pQ2wEr5t' would be applied to SSID 'ISStation_Guest'
[INFO] ... Script execution completed successfully (simulation mode - no changes applied)
```

**Real Mode**:
```
[INFO] ... WiFi password updated successfully on UDM Pro (HTTP 200) using X-API-KEY
[INFO] ... Access Points will automatically reprovision with new configuration within 1-2 minutes
[INFO] ... HA entity input_text.guest_wifi_password updated successfully (HTTP 200) using Bearer token
[INFO] ... Script execution completed successfully (changes applied successfully)
```

### Automation Examples

#### Home Assistant Automation (Monthly Password Change)
```yaml
automation:
  - alias: "Change Guest WiFi Password Monthly"
    trigger:
      - platform: time
        at: "02:00:00"  # 2 AM first day of month
    condition:
      - condition: template
        value_template: "{{ now().day == 1 }}"
    action:
      - service: shell_command.guest_wifi_change
        data: {}
```

#### Shell Command in HA `configuration.yaml`
```yaml
shell_command:
  guest_wifi_change: '/config/scripts/change_guest_pass.sh "{{ password|default('') }}"'
```

#### Cron Job (Linux/HA Host)
```bash
# Monthly at 2 AM (edit crontab: crontab -e)
0 2 1 * * /path/to/change_guest_pass.sh >> /var/log/guest_wifi.log 2>&1
```

## Configuration Details

### secrets.yaml Format
- **YAML Indentation**: Use 2 spaces (standard YAML).
- **Comments**: Inline comments supported (e.g., `udm_host: 192.168.1.1 # UDM Pro LAN IP`).
- **Quotes**: Optional for strings without spaces; required for SSIDs with spaces.
- **Security**: Store outside git (add to `.gitignore`). Use file permissions `600` (owner read/write only).

Example with comments:
```yaml
# UDM Pro Configuration
udm_host: 192.168.1.1  # UDM Pro IP (LAN interface)
udm_api_key: eyJ0eXAiOiJKV1QiLCdupa-dupaJhbGciOiJIUzI1NiJ9...  # Full API token

# Home Assistant Configuration
ha_url: homeassistant.local  # HA hostname (no protocol/port)
ha_llat_token: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...  # LLAT with API access

# WiFi Network
guest_lan: "Guest Network 2.4GHz"  # Exact SSID from UDM WiFi settings
```

### API Endpoints
- **UDM Pro GET WLANs**: `https://{{udm_host}}/proxy/network/api/s/default/rest/wlanconf` (X-API-KEY).
- **UDM Pro PUT Password**: `https://{{udm_host}}/proxy/network/api/s/default/rest/wlanconf/{{ssid_id}}` (JSON: `{"_id": "{{ssid_id}}", "x_passphrase": "{{new_password}}"}`).
- **HA Update Entity**: `https://{{ha_url}}:8123/api/states/input_text.guest_wifi_password` (Bearer token, JSON: `{"state": "{{new_password}}"}`).

## Troubleshooting

### Common Issues

1. **"Missing udm_host" Error**:
   - Check `secrets.yaml` indentation and key spelling (`udm_host:` not `udm-host:`).
   - Verify no trailing spaces or invalid YAML.
   - Run: `grep udm_host /config/secrets.yaml` – should show the line.

2. **401 Unauthorized (UDM)**:
   - Regenerate API key in UDM > Settings > Control Plane > Integrations > New Key.
   - Ensure "Owner" role and full "Network" permissions.

3. **404 Not Found (SSID)**:
   - Run in test mode (`-t`) to list available SSIDs in logs.
   - Verify exact SSID name in UDM UI (case-sensitive, including spaces).

4. **HA 401/403**:
   - Regenerate LLAT in HA > Profile > Long-Lived Access Tokens.
   - Ensure token has "Read/Write" API access.

5. **Password Length Error**:
   - UniFi requires exactly 16 characters for WPA2/3-PSK.
   - Custom passwords must be 16 chars; script generates compliant ones automatically.

6. **Curl/Connectivity Issues**:
   - Test UDM: `curl -k -H "X-API-KEY: $API_KEY" https://$UDM_HOST/proxy/network/api/s/default/rest/wlanconf | jq .` (install `jq` for JSON pretty-print).
   - Test HA: `curl -H "Authorization: Bearer $HA_TOKEN" https://$HA_URL:8123/api/states/input_text.guest_wifi_password`.
   - Disable SSL verification with `-k` (self-signed certs common).

### Logs
- **Log File**: `/config/scripts/change_guest_wifi.log` (appended with timestamps).
- **Debug Mode**: Run with `-t` and check logs for raw API responses and parsed values.

### Testing Workflow
1. Validate secrets: `./change_guest_pass.sh -t | grep "UDM Host\|Target SSID"`.
2. Verify SSID: Look for "Found matching SSID" in logs.
3. Simulate full run: `./change_guest_pass.sh -t`.
4. Real run: `./change_guest_pass.sh`.

## Security Notes

- **API Keys/Tokens**: Never commit to git. Use `.gitignore` for `secrets.yaml`.
- **Password Exposure**: Logs show generated passwords – secure log access (e.g., HA add-on logs are internal).
- **Network Access**: Script assumes LAN connectivity to UDM/HA. Use VPN for remote access.
- **HTTPS**: Uses `-k` (insecure) for self-signed certs; consider proper CA setup for production.
- **Permissions**: Script runs as non-root; ensure `curl` access to network.

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Commit changes (`git commit -m 'Add amazing feature'`).
4. Push to branch (`git push origin feature/amazing-feature`).
5. Open Pull Request.

### Development
- Test in Docker: `docker run -v $(pwd):/config alpine sh -c "apk add curl bash && ./change_guest_pass.sh -t"`.
- Lint: Use `shellcheck change_guest_pass.sh` for bash syntax checks.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Ubiquiti Networks for UDM Pro API.
- Home Assistant community for REST API integration.
- BusyBox maintainers for lightweight Unix tools.

***

*Built for Home Assistant users managing Ubiquiti networks. Questions? Open an issue.*
#!/bin/bash
#
# fan-logger.sh - Continuous fan/temperature logger for mbpfan
# Logs temp, RPM, expected RPM every polling_interval seconds
# Rotates logs daily, compresses old ones
#
# Usage: fan-logger.sh &
#   or via systemd: systemctl start mbpfan-logger
#

set -e
set +o pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$REPO_DIR/logs"
CORETEMP="/sys/devices/platform/coretemp.0/hwmon"
FAN_INPUT="/sys/devices/platform/applesmc.768/fan1_input"

# Find hwmon device
HWMON=$(ls -d $CORETEMP/hwmon* 2>/dev/null | head -1)
if [ -z "$HWMON" ]; then
    echo "Error: coretemp hwmon not found" >&2
    exit 1
fi
TEMP_FILE="$HWMON/temp1_input"

# Curve points (match src/mbpfan.c fan_curve[])
declare -a temps=(70 75 80 85 88 90 92 94 96 98 100)
declare -a rpms=(2100 2400 2600 2800 3200 3500 3900 4300 4800 5500 6100)

get_top_processes() {
    # Get top 3 processes by CPU usage (comma-separated, quoted)
    ps aux --sort=-%cpu 2>/dev/null | tail -n +2 | head -3 | \
        awk '{printf "%s(%.1f%%);", $11, $3}' 2>/dev/null | \
        sed 's/;$//' 2>/dev/null | \
        sed 's/;/|/g' 2>/dev/null || echo ""
}

get_expected_rpm() {
    local temp=$1
    if [ $temp -le 70 ]; then echo 2100; return; fi
    if [ $temp -ge 100 ]; then echo 6100; return; fi

    for i in {0..9}; do
        local t1=${temps[$i]} t2=${temps[$((i+1))]}
        local r1=${rpms[$i]} r2=${rpms[$((i+1))]}

        if [ $temp -le $t2 ]; then
            local span=$((t2 - t1))
            local rpm_span=$((r2 - r1))
            local pos=$((temp - t1))
            echo $(( r1 + (pos * rpm_span) / span ))
            return
        fi
    done
    echo 6100
}

# Rotate logs if needed (daily)
rotate_logs() {
    local today=$(date +%Y-%m-%d)
    local current_log="$LOG_DIR/fan-$today.csv"

    # If log exists but date changed, compress yesterday's
    if [ -f "$current_log" ]; then
        return  # Same day, no rotation needed
    fi

    # Compress logs older than today
    for old_log in "$LOG_DIR"/fan-*.csv; do
        if [ -f "$old_log" ] && [ "$old_log" != "$current_log" ]; then
            if [ ! -f "$old_log.gz" ]; then
                gzip "$old_log" 2>/dev/null || true
            fi
        fi
    done
}

# Main logging loop
main_loop() {
    mkdir -p "$LOG_DIR"

    logger -t fan-logger "Starting: logs in $LOG_DIR"

    while true; do
        rotate_logs

        local today=$(date +%Y-%m-%d)
        local log_file="$LOG_DIR/fan-$today.csv"

        # Create header if new file
        if [ ! -f "$log_file" ]; then
            echo "timestamp,temp_c,fan_rpm,expected_rpm,diff,status,top_3_processes" > "$log_file"
        fi

        # Read values
        local temp_raw=$(cat "$TEMP_FILE" 2>/dev/null)
        local fan_rpm=$(cat "$FAN_INPUT" 2>/dev/null)

        if [ -z "$temp_raw" ] || [ -z "$fan_rpm" ]; then
            sleep 1
            continue
        fi

        local temp_c=$((temp_raw / 1000))
        local expected_rpm=$(get_expected_rpm $temp_c)
        local diff=$((fan_rpm - expected_rpm))

        # Determine status
        local status="OK"
        if [ $fan_rpm -gt $((expected_rpm + 250)) ]; then
            status="TOO_HIGH"
        elif [ $fan_rpm -lt $((expected_rpm - 250)) ]; then
            status="TOO_LOW"
        fi

        # Log entry
        local timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
        local top_processes=$(get_top_processes)
        echo "$timestamp,$temp_c,$fan_rpm,$expected_rpm,$diff,$status,\"$top_processes\"" >> "$log_file"

        # Sync every 10 entries to prevent data loss
        local lines=$(wc -l < "$log_file")
        if [ $((lines % 10)) -eq 0 ]; then
            sync "$log_file"
        fi

        # Sleep polling_interval (usually 1 second)
        sleep 1
    done
}

# Signal handlers
trap 'logger -t fan-logger "Stopping"; exit 0' SIGTERM SIGINT

main_loop

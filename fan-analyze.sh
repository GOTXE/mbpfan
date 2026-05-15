#!/bin/bash
#
# fan-analyze.sh - Analyze fan logs, extract metrics and anomalies
#
# Usage:
#   ./fan-analyze.sh                    # Analyze today's log
#   ./fan-analyze.sh 2026-05-12         # Analyze specific date
#   ./fan-analyze.sh --all              # Summarize all logs
#

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$REPO_DIR/logs"

analyze_log() {
    local log_file=$1
    local date_label=$(basename "$log_file" | sed 's/fan-//;s/.csv.*//')

    if [ ! -f "$log_file" ]; then
        echo "Log not found: $log_file"
        return 1
    fi

    # Skip header
    local data=$(tail -n +2 "$log_file")

    if [ -z "$data" ]; then
        echo "No data in $log_file"
        return 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "Fan Log Analysis — $date_label"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Extract columns
    local temps=$(echo "$data" | cut -d, -f2)
    local rpms=$(echo "$data" | cut -d, -f3)
    local expected=$(echo "$data" | cut -d, -f4)
    local diffs=$(echo "$data" | cut -d, -f5)
    local status=$(echo "$data" | cut -d, -f6)

    # Temperature stats
    echo "📊 TEMPERATURE"
    echo "  Current entries: $(echo "$data" | wc -l)"
    echo "  Min:  $(echo "$temps" | sort -n | head -1)°C"
    echo "  Max:  $(echo "$temps" | sort -n | tail -1)°C"
    echo "  Avg:  $(echo "$temps" | awk '{sum+=$1} END {printf "%.1f", sum/NR}')°C"
    echo ""

    # Fan RPM stats
    echo "🌀 FAN RPM (Actual)"
    echo "  Min:  $(echo "$rpms" | sort -n | head -1) RPM"
    echo "  Max:  $(echo "$rpms" | sort -n | tail -1) RPM"
    echo "  Avg:  $(echo "$rpms" | awk '{sum+=$1} END {printf "%.0f", sum/NR}') RPM"
    echo ""

    # Expected RPM stats
    echo "🎯 FAN RPM (Expected per curve)"
    echo "  Min:  $(echo "$expected" | sort -n | head -1) RPM"
    echo "  Max:  $(echo "$expected" | sort -n | tail -1) RPM"
    echo "  Avg:  $(echo "$expected" | awk '{sum+=$1} END {printf "%.0f", sum/NR}') RPM"
    echo ""

    # Anomalies
    local too_high=$(echo "$status" | grep -c "TOO_HIGH" || true)
    local too_low=$(echo "$status" | grep -c "TOO_LOW" || true)
    local ok_count=$(echo "$status" | grep -c "OK" || true)

    echo "⚠️  STATUS SUMMARY"
    echo "  OK:       $ok_count entries"
    echo "  TOO_HIGH: $too_high entries (fan >250 RPM above expected)"
    echo "  TOO_LOW:  $too_low entries (fan >250 RPM below expected)"
    echo ""

    # Temperature jumps
    local temp_jumps=$(echo "$temps" | awk '
        NR > 1 {
            delta = $1 - prev
            if (delta > 10 || delta < -10) jumps++
        }
        { prev = $1 }
        END { print jumps+0 }
    ')

    echo "🔔 ANOMALIES"
    echo "  Temp jumps (>10°C): $temp_jumps"
    echo ""

    # Peak events
    echo "📈 PEAK EVENTS (Top 3 fan speeds)"
    echo "$data" | sort -t, -k3 -rn | head -3 | awk -F, '{
        printf "  %s | Temp: %d°C, RPM: %d (expected: %d, diff: %d)\n",
        $1, $2, $3, $4, $5
    }'
    echo ""

    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

# Check arguments
if [ "$1" = "--all" ]; then
    echo "Analyzing all available logs..."
    echo ""
    for log in "$LOG_DIR"/fan-*.csv "$LOG_DIR"/fan-*.csv.gz; do
        if [ -f "$log" ]; then
            if [[ "$log" == *.gz ]]; then
                zcat "$log" | (cat <(echo "timestamp,temp_c,fan_rpm,expected_rpm,diff,status"); tail -n +2) > /tmp/fan-analyze-tmp.csv
                analyze_log /tmp/fan-analyze-tmp.csv
            else
                analyze_log "$log"
            fi
        fi
    done
elif [ -n "$1" ]; then
    # Specific date
    local date=$1
    local log_file="$LOG_DIR/fan-$date.csv"
    analyze_log "$log_file"
else
    # Today's log
    local today=$(date +%Y-%m-%d)
    local log_file="$LOG_DIR/fan-$today.csv"
    analyze_log "$log_file"
fi

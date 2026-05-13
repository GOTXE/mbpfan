#!/bin/bash

CORETEMP_PATH="/sys/devices/platform/coretemp.0/hwmon"
if [ ! -d "$CORETEMP_PATH" ]; then
    echo "coretemp not found"
    exit 1
fi

HWMON=$(ls -d $CORETEMP_PATH/hwmon* 2>/dev/null | head -1)
if [ -z "$HWMON" ]; then
    echo "hwmon not found"
    exit 1
fi

TEMP_FILE="$HWMON/temp1_input"
FAN_FILE="/sys/devices/platform/applesmc.768/fan1_input"

echo "Monitoreando: temp=$TEMP_FILE, fan=$FAN_FILE"
echo ""
echo "TEMP(C)  FAN_RPM  EXPECTED_RPM  DIFF      NOTES"
echo "=========================================="

# Array con curva hardcodeada del código
declare -a temps=(70 75 80 85 88 90 92 94 96 98 100)
declare -a rpms=(2100 2400 2600 2800 3200 3500 3900 4300 4800 5500 6100)

get_expected_rpm() {
    local temp=$1
    if [ $temp -le 70 ]; then
        echo 2100
        return
    fi
    if [ $temp -ge 100 ]; then
        echo 6100
        return
    fi
    
    # Interpolación lineal
    for i in {0..9}; do
        t1=${temps[$i]}
        t2=${temps[$((i+1))]}
        r1=${rpms[$i]}
        r2=${rpms[$((i+1))]}
        
        if [ $temp -le $t2 ]; then
            # Interpolate
            local span=$((t2 - t1))
            local rpm_span=$((r2 - r1))
            local pos=$((temp - t1))
            local result=$(( r1 + (pos * rpm_span) / span ))
            echo $result
            return
        fi
    done
    echo 6100
}

for i in {1..30}; do
    temp_raw=$(cat "$TEMP_FILE" 2>/dev/null)
    if [ -z "$temp_raw" ]; then
        echo "Error reading temp"
        break
    fi
    
    temp_c=$((temp_raw / 1000))
    
    # Leer RPM del fan
    fan_rpm=$(cat "$FAN_FILE" 2>/dev/null)
    if [ -z "$fan_rpm" ]; then
        fan_rpm="N/A"
    fi
    
    expected=$(get_expected_rpm $temp_c)
    
    if [ "$fan_rpm" = "N/A" ]; then
        diff="N/A"
    else
        diff=$((fan_rpm - expected))
    fi
    
    printf "%-7d %-7s %-12d %-9s " "$temp_c" "$fan_rpm" "$expected" "$diff"
    
    if [ "$fan_rpm" != "N/A" ] && [ $fan_rpm -gt $((expected + 250)) ]; then
        echo "TOO_HIGH (histéresis?)"
    elif [ "$fan_rpm" != "N/A" ] && [ $fan_rpm -lt $((expected - 250)) ]; then
        echo "TOO_LOW"
    else
        echo "OK"
    fi
    
    sleep 1
done

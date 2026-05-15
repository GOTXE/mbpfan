commit 4597362d7256ba3306e0fcffab885e584be8ac8c
Author: gotxe <github.facelift473@slmail.me>
Date:   Wed May 13 22:27:55 2026 +0200

    feat: mbpfan mod for MBP 2015 + CachyOS - v4 complete implementation
    
    Core Features:
    ============
    
    1. Temperature Sensor Filtering (src/mbpfan.c)
       - Read ONLY coretemp Package id 0 (ignore applesmc fake sensors)
       - Rate limiter: +15°C/cycle max (smooth ramps, reject spikes >15°C)
       - Reject upward jumps, allow downward cooling without limit
    
    2. Progressive Fan Curve (src/mbpfan.c)
       - Hardcoded 11-point table: 70°C@2100RPM → 100°C@6100RPM
       - Linear interpolation between points
       - No oscillations: histeresis +250 RPM/cycle on upward, 4-cycle downramp
    
    3. Fan Control Hysteresis (src/mbpfan.c)
       - Upward: limited by rate limiter temp (+15°C/cycle)
       - Downward: 4-cycle progressive (diff/4 per cycle)
       - Example: 6100→2100 RPM drops 1000/cycle in 4 cycles
    
    4. Configuration (mbpfan.conf)
       - min_fan1_speed = 2000 RPM (operational minimum)
       - max_fan1_speed = 6199 RPM
       - Thresholds: low_temp=70, high_temp=85, max_temp=96
       - polling_interval = 1 second
    
    5. Monitoring Scripts (new)
       - monitor_detailed.sh: real-time temp vs expected RPM
       - monitor_realtime.sh: simple system monitoring
    
    Documentation (new):
       - CAMBIOS.md: detailed change log with algorithms
       - DATOS_TECNICOS.md: technical implementation details
       - ESTADO.md: validation status and test results
       - SIGUIENTE.md: next steps (stress test, fork strategy)
    
    Tested on:
      - MBP 13" Retina 2015 (MacBookPro12,1)
      - CachyOS Linux (kernel 7.0.5-2-cachyos)
      - Intel Core i5-5257U (Broadwell)
      - Without load: temp <70°C, fan silent @2100 RPM
      - With stress: temp 60→105°C smooth ramp, no oscillations
    
    Co-Authored-By: gotxe <github.facelift473@slmail.me>

diff --git a/monitor_detailed.sh b/monitor_detailed.sh
new file mode 100755
index 0000000..90f4f18
--- /dev/null
+++ b/monitor_detailed.sh
@@ -0,0 +1,92 @@
+#!/bin/bash
+
+CORETEMP_PATH="/sys/devices/platform/coretemp.0/hwmon"
+if [ ! -d "$CORETEMP_PATH" ]; then
+    echo "coretemp not found"
+    exit 1
+fi
+
+HWMON=$(ls -d $CORETEMP_PATH/hwmon* 2>/dev/null | head -1)
+if [ -z "$HWMON" ]; then
+    echo "hwmon not found"
+    exit 1
+fi
+
+TEMP_FILE="$HWMON/temp1_input"
+FAN_FILE="/sys/devices/platform/applesmc.768/fan1_input"
+
+echo "Monitoreando: temp=$TEMP_FILE, fan=$FAN_FILE"
+echo ""
+echo "TEMP(C)  FAN_RPM  EXPECTED_RPM  DIFF      NOTES"
+echo "=========================================="
+
+# Array con curva hardcodeada del código
+declare -a temps=(70 75 80 85 88 90 92 94 96 98 100)
+declare -a rpms=(2100 2400 2600 2800 3200 3500 3900 4300 4800 5500 6100)
+
+get_expected_rpm() {
+    local temp=$1
+    if [ $temp -le 70 ]; then
+        echo 2100
+        return
+    fi
+    if [ $temp -ge 100 ]; then
+        echo 6100
+        return
+    fi
+    
+    # Interpolación lineal
+    for i in {0..9}; do
+        t1=${temps[$i]}
+        t2=${temps[$((i+1))]}
+        r1=${rpms[$i]}
+        r2=${rpms[$((i+1))]}
+        
+        if [ $temp -le $t2 ]; then
+            # Interpolate
+            local span=$((t2 - t1))
+            local rpm_span=$((r2 - r1))
+            local pos=$((temp - t1))
+            local result=$(( r1 + (pos * rpm_span) / span ))
+            echo $result
+            return
+        fi
+    done
+    echo 6100
+}
+
+for i in {1..30}; do
+    temp_raw=$(cat "$TEMP_FILE" 2>/dev/null)
+    if [ -z "$temp_raw" ]; then
+        echo "Error reading temp"
+        break
+    fi
+    
+    temp_c=$((temp_raw / 1000))
+    
+    # Leer RPM del fan
+    fan_rpm=$(cat "$FAN_FILE" 2>/dev/null)
+    if [ -z "$fan_rpm" ]; then
+        fan_rpm="N/A"
+    fi
+    
+    expected=$(get_expected_rpm $temp_c)
+    
+    if [ "$fan_rpm" = "N/A" ]; then
+        diff="N/A"
+    else
+        diff=$((fan_rpm - expected))
+    fi
+    
+    printf "%-7d %-7s %-12d %-9s " "$temp_c" "$fan_rpm" "$expected" "$diff"
+    
+    if [ "$fan_rpm" != "N/A" ] && [ $fan_rpm -gt $((expected + 250)) ]; then
+        echo "TOO_HIGH (histéresis?)"
+    elif [ "$fan_rpm" != "N/A" ] && [ $fan_rpm -lt $((expected - 250)) ]; then
+        echo "TOO_LOW"
+    else
+        echo "OK"
+    fi
+    
+    sleep 1
+done

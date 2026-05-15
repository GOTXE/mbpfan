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

diff --git a/monitor_realtime.sh b/monitor_realtime.sh
new file mode 100755
index 0000000..8bc83d0
--- /dev/null
+++ b/monitor_realtime.sh
@@ -0,0 +1,33 @@
+#!/bin/bash
+# Monitorear en tiempo real durante pruebas
+
+INTERVAL="${1:-1}"  # segundos (default 1)
+
+echo "=== Monitor tiempo real mbpfan ==="
+echo "Intervalo: $INTERVAL segundos"
+echo "Presiona Ctrl+C para detener"
+echo ""
+
+while true; do
+    clear
+    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
+    echo ""
+    
+    echo "--- TEMPERATURA ---"
+    sensors | grep -E "Package id|Core"
+    echo ""
+    
+    echo "--- RPM VENTILADOR ---"
+    RPM=$(cat /sys/devices/platform/applesmc.768/fan1_output)
+    echo "RPM actual: $RPM"
+    echo ""
+    
+    echo "--- CARGA SISTEMA ---"
+    uptime
+    echo ""
+    
+    echo "--- ERRORES RECIENTES ---"
+    journalctl -u mbpfan -n 5 --no-pager 2>/dev/null || echo "(sin logs)"
+    
+    sleep "$INTERVAL"
+done

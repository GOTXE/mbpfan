#!/bin/bash
# Monitorear en tiempo real durante pruebas

INTERVAL="${1:-1}"  # segundos (default 1)

echo "=== Monitor tiempo real mbpfan ==="
echo "Intervalo: $INTERVAL segundos"
echo "Presiona Ctrl+C para detener"
echo ""

while true; do
    clear
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    
    echo "--- TEMPERATURA ---"
    sensors | grep -E "Package id|Core"
    echo ""
    
    echo "--- RPM VENTILADOR ---"
    RPM=$(cat /sys/devices/platform/applesmc.768/fan1_output)
    echo "RPM actual: $RPM"
    echo ""
    
    echo "--- CARGA SISTEMA ---"
    uptime
    echo ""
    
    echo "--- ERRORES RECIENTES ---"
    journalctl -u mbpfan -n 5 --no-pager 2>/dev/null || echo "(sin logs)"
    
    sleep "$INTERVAL"
done

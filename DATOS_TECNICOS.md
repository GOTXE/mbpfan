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

diff --git a/DATOS_TECNICOS.md b/DATOS_TECNICOS.md
new file mode 100644
index 0000000..866cc46
--- /dev/null
+++ b/DATOS_TECNICOS.md
@@ -0,0 +1,271 @@
+# Datos Técnicos — MBP 13" Retina 2015 + CachyOS
+
+## Hardware
+
+- **Modelo**: MacBook Pro 13" Retina 2015
+- **Código**: MacBookPro12,1
+- **SO**: CachyOS Linux (kernel 7.0.5-2-cachyos)
+- **CPU**: Intel Core i5-5257U (Broadwell)
+- **RAM**: 8GB LPDDR3
+- **Fans**: 1 ventilador (fan1)
+
+## Controladores del sistema
+
+### applesmc
+- **Interfaz**: `/sys/devices/platform/applesmc.768/`
+- **Fan mínimo**: [revisar `fan1_min`]
+- **Fan máximo**: [revisar `fan1_max`]
+- **Fan actual**: [revisar `fan1_output`]
+
+### coretemp
+- **Interfaz**: `/sys/class/thermal/` y `hwmon/`
+- **Temperatura CPU**: lee desde `coretemp` (por core).
+- **Temp crítica**: ~105°C (Intel PROCHOT).
+
+## Umbrales térmicos
+
+| Zona | Rango | Acción |
+|---|---:|---|
+| Normal | 0–70°C | Ventilador pasivo (2000 RPM) |
+| Caliente | 70–85°C | Rampa suave |
+| Muy caliente | 85–96°C | Rampa agresiva |
+| Peligro | 96–100°C | Ventilador alto (4400+ RPM) |
+| Crítica | ≥100°C | Máximo o casi máximo |
+| PROCHOT | ≥102°C | Situación anómala — alerta |
+
+## mbpfan instalado
+
+- **Versión**: 2.4.0-7 (desde AUR/paru).
+- **Binario**: `/usr/sbin/mbpfan`.
+- **Config**: `/etc/mbpfan.conf`.
+- **Servicio**: `mbpfan.service` (systemd).
+
+## Valores actuales
+
+```ini
+[general]
+min_fan1_speed = 2000
+max_fan1_speed = 6199
+low_temp = 70
+high_temp = 85
+max_temp = 96
+polling_interval = 1
+```
+
+## Instalación
+
+- **Fecha**: 11 may 2026 12:31:12 (Original).
+- **Método**: Parche local post-instalación.
+- **Última modificación**: 13 may 2026 (v3: Filtro de picos).
+
+---
+
+## Implementación de Mejoras (v3)
+
+### 1. Filtro de Sensores
+
+**Ubicación**: `mbpfan.c` línea 161-265
+
+**Problema original**: mbpfan leía TODOS los sensores disponibles:
+```
+/sys/devices/platform/coretemp.0/hwmon/hwmon0/temp1_input  → 62°C ✓
+/sys/devices/platform/coretemp.0/hwmon/hwmon0/temp2_input  → 65°C (Core 1)
+/sys/devices/platform/applesmc.768/...                      → -127°C ✗
+/sys/devices/platform/pch_thermal/...                       → -42.8°C ✗
+```
+
+**Solución**: Leer SOLO `temp1_input` (Package id 0 = máximo de cores):
+```c
+path = smprintf("%s/temp1_input", hwmon_path);
+// Ignora temp2, temp3, applesmc, pch, BAT0
+```
+
+**Lectura de sensor**:
+```bash
+$ cat /sys/devices/platform/coretemp.0/hwmon/hwmon1/temp1_input
+62000  # En milígrados (62°C)
+```
+
+### 2. Curva Progresiva con Interpolación
+
+**Ubicación**: `mbpfan.c` líneas 86-98, 490-511
+
+**Tabla hardcodeada**:
+```c
+static const t_curve_point fan_curve[] = {
+    {70, 2100},    // 70°C  → 2100 RPM (mínimo operacional)
+    {75, 2400},    // 75°C  → 2400 RPM
+    {80, 2600},    // 80°C  → 2600 RPM
+    {85, 2800},    // 85°C  → 2800 RPM
+    {88, 3200},    // 88°C  → 3200 RPM
+    {90, 3500},    // 90°C  → 3500 RPM
+    {92, 3900},    // 92°C  → 3900 RPM
+    {94, 4300},    // 94°C  → 4300 RPM
+    {96, 4800},    // 96°C  → 4800 RPM
+    {98, 5500},    // 98°C  → 5500 RPM
+    {100, 6100},   // 100°C → 6100 RPM (máximo)
+};
+```
+
+**Interpolación lineal** (función `interpolate_curve_speed()`):
+
+Para temperatura = 77°C:
+```
+Entre punto (75, 2400) y (80, 2600):
+  temp_span = 80 - 75 = 5°C
+  rpm_span = 2600 - 2400 = 200 RPM
+  pos = 77 - 75 = 2°C
+  rpm = 2400 + (2/5) * 200 = 2400 + 80 = 2480 RPM
+```
+
+**Histeresis de bajada**: Limita caída máxima a 250 RPM/ciclo
+```c
+if (temp_c >= 98 && target_speed < 5200) {
+    target_speed = 5200;  // Fuerza mínimo si está cerca de crítica
+}
+
+if (fan->old_speed > 0 && target_speed < fan->old_speed) {
+    target_speed = max(target_speed, fan->old_speed - 250);
+}
+```
+
+Ejemplo:
+```
+Ciclo 1: 94°C → 4300 RPM (old_speed = 4300)
+Ciclo 2: 65°C → esperado 2100, pero old_speed=4300
+         → actual = max(2100, 4300-250) = 4050 RPM
+Ciclo 3: 65°C → actual = max(2100, 4050-250) = 3800 RPM
+Ciclo 4: 65°C → actual = max(2100, 3800-250) = 3550 RPM
+...
+Ciclo 10: 65°C → actual = 2100 RPM (llega a target)
+```
+
+**Beneficio**: Suaviza bajadas, evita saltos de RPM audibles.
+
+### 3. Filtro de Picos de Temperatura
+
+**Ubicación**: `mbpfan.c` líneas 82-100
+
+**Problema**: Sensor coretemp reporta picos ruidosos de ±30°C en 1-2 ciclos:
+```
+Lectura real:  60 → 60 → 91 (spike) → 65 → 60 → 60 → ...
+               └─ Cambio +31°C en 1 ciclo (ruido del sensor)
+```
+
+**Solución**: Rechaza cambios >10°C hacia ARRIBA, permite bajadas:
+```c
+static unsigned short filter_temp_spikes(unsigned short new_temp)
+{
+    int delta = new_temp - last_valid_temp;
+    
+    if (delta > 10) {
+        // Upward spike detected - REJECT
+        return last_valid_temp;  // Mantiene lectura anterior
+    }
+    
+    // Downward change or small upward - ACCEPT
+    last_valid_temp = new_temp;
+    return new_temp;
+}
+```
+
+**Aplicación en loop principal**:
+```c
+new_temp = get_temp(sensors);              // Lee 60°C
+new_temp = filter_temp_spikes(new_temp);   // Verifica: 60-60=0, OK → 60°C
+
+new_temp = get_temp(sensors);              // Lee 91°C
+new_temp = filter_temp_spikes(new_temp);   // Verifica: 91-60=+31, SPIKE → 60°C (mantiene)
+
+new_temp = get_temp(sensors);              // Lee 65°C
+new_temp = filter_temp_spikes(new_temp);   // Verifica: 65-60=+5, OK → 65°C
+```
+
+**Diferencia delta=10°C**:
+- Rechaza: +31°C, +25°C, +20°C, +11°C (picos ruidosos)
+- Permite: +5°C, -10°C, -35°C (cambios reales)
+
+---
+
+## Polling Interval
+
+**Configuración**: `polling_interval = 1` (1 segundo por ciclo)
+
+**Loop principal** (línea 748-794):
+```c
+while (1) {
+    new_temp = get_temp(sensors);
+    new_temp = filter_temp_spikes(new_temp);
+    
+    for each fan:
+        fan_speed = compute_curve_fan_speed(fan, new_temp);
+        set_fan_speed(fan, fan_speed);
+    
+    nanosleep(1 segundo);  // Espera 1 segundo antes del próximo ciclo
+}
+```
+
+Con `polling_interval=1`:
+- 3 ciclos = 3 segundos
+- 60 ciclos = 60 segundos
+
+---
+
+## Lectura de Fan y Control
+
+### Lectura de RPM actual
+```bash
+$ cat /sys/devices/platform/applesmc.768/fan1_input
+2100
+# = 2100 RPM actualmente
+```
+
+### Escritura de RPM (pwm)
+```bash
+$ cat /sys/devices/platform/applesmc.768/fan1_output
+2100
+$ echo 3500 | sudo tee /sys/devices/platform/applesmc.768/fan1_output
+# Intenta setear a 3500 RPM
+```
+
+### Rango válido
+```bash
+$ cat /sys/devices/platform/applesmc.768/fan1_min
+0
+$ cat /sys/devices/platform/applesmc.768/fan1_max
+6199
+# Rango: 0-6199 RPM
+```
+
+**mbpfan clampea a**: `min_fan1_speed=2000` a `max_fan1_speed=6199`
+```c
+target_speed = clamp_fan_speed(fan, target_speed);
+// if (target_speed < 2000) target_speed = 2000;
+// if (target_speed > 6199) target_speed = 6199;
+```
+
+---
+
+## Monitoreo en Vivo
+
+### Script de monitoreo
+```bash
+/home/gtx/Documentos/GITHUB/mbpfan_mod/mbpfan-local-repo/monitor_detailed.sh
+```
+
+Muestra:
+- Temperatura filtrada (POST-filtro)
+- RPM actual
+- RPM esperado según curva
+- Diferencia (si RPM > esperado+250 = TOO_HIGH, < esperado-250 = TOO_LOW)
+
+### Logs del servicio
+```bash
+sudo journalctl -u mbpfan -f --no-pager
+```
+
+Con verbose (`sudo /usr/sbin/mbpfan -v`):
+```
+[...] Curve Temp: 72 Fan: fan1 Speed: 2220 Max MHz: 2700
+[...] Curve Temp: 65 Fan: fan1 Speed: 2100 Max MHz: 2700
+```

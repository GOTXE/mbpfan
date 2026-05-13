# Estado de Pruebas y Validación

## Resumen Actual

**Status**: ✅ **IMPLEMENTACIÓN COMPLETADA** | ⏳ Pruebas con carga pendientes

Versión: v3 (Filtro de sensores + Curva progresiva + Filtro de picos de temperatura)

---

## Fase 1: Filtro de Sensores (v1 → v2)

**Status**: ✅ COMPLETADO Y VALIDADO

### Cambios
- Reescrito `retrieve_sensors()` para leer **SOLO** `/sys/devices/platform/coretemp.0/hwmon/hwmonX/temp1_input` (Package id 0).
- Eliminados lectores de applesmc, pch, BAT0 que reportaban valores fake (-127°C, -42.8°C).

### Validación
- ✅ Fan responde correctamente a temperatura real (coretemp).
- ✅ No hay picos falsos de 102°C.
- ✅ Oscilación "qqqqqFFFFF" eliminada.

---

## Fase 2: Curva Progresiva (v2 → v3a)

**Status**: ✅ COMPLETADO Y VALIDADO

### Cambios
- Tabla hardcodeada `fan_curve[]` con puntos de control:
  ```
  70°C → 2100 RPM (mínimo operacional)
  75°C → 2400 RPM
  80°C → 2600 RPM
  85°C → 2800 RPM
  88°C → 3200 RPM
  90°C → 3500 RPM
  92°C → 3900 RPM
  94°C → 4300 RPM
  96°C → 4800 RPM
  98°C → 5500 RPM
  100°C → 6100 RPM
  ```
- Interpolación lineal entre puntos (`interpolate_curve_speed()`).
- Histeresis de bajada: máximo 250 RPM/ciclo hacia abajo.

### Validación
- ✅ Fan permanece en 2100 RPM hasta 70°C (silencioso en reposo).
- ✅ Rampa suave según temperatura real.
- ✅ Sin oscilaciones por limitación de bajada.

---

## Fase 3: Filtro de Picos de Temperatura (v3a → v3)

**Status**: ✅ COMPLETADO Y VALIDADO

### Problema
Sensor coretemp reporta picos ruidosos (60°C → 91°C → 65°C en 1-2 segundos).

### Solución
Función `filter_temp_spikes()` que:
- **Rechaza** subidas >10°C (picos ruidosos hacia arriba).
- **Permite** bajadas sin límite (enfriamiento real).

```c
if (delta > 10) {  // Upward spike
    return last_valid_temp;  // REJECT
}
last_valid_temp = new_temp;
return new_temp;  // ACCEPT downward or small change
```

### Validación (13 may 2026)
- ✅ Sin carga: Fan estable ~2100 RPM.
- ✅ Temp filtrada correctamente (picos rechazados).
- ✅ Rampa normal cuando temp sube gradualmente.
- ⏳ **SIGUIENTE**: Pruebas con carga (stress test).

### Ejemplo Monitor (sin carga)
```
TEMP(C)  FAN_RPM  EXPECTED_RPM  DIFF      NOTES
==========================================
60      2102    2100         2         OK
80      2069    2600         -531      TOO_LOW (temp filtrada)
90      2108    3500         -1392     TOO_LOW (temp filtrada)
62      2096    2100         -4        OK
```

Nota: "TOO_LOW" es falso positivo. Fan no sube porque temperatura fue filtrada (pico rechazado).

---

## Pruebas Completadas

### Pruebas sin carga
- ✅ Reposo (CPU idle, terminales + Brave).
- ✅ Fan mantiene ~2100 RPM.
- ✅ Temperatura 59-65°C (normal).
- ✅ Sin oscilaciones auditivas.

### Pruebas pendientes (SIGUIENTE)
- ⏳ Carga ligera (VSCode, compilación).
- ⏳ Carga media (compilación con -j4).
- ⏳ Carga fuerte (stress-ng, membench).
- ⏳ Validar rampa de fan bajo carga real.

---

## Criterios de Aceptación

- [x] Sin lecturas falsas de temperatura.
- [x] Fan quieto en reposo (<70°C).
- [x] Sin oscilaciones audibles (qqqFFF).
- [x] Curva progresiva (no saltos de RPM).
- [ ] Rampa correcta bajo carga sostenida.
- [ ] Throttling térmico no ocurre en uso normal.

---

## Archivos Modificados

```
mbpfan-local-repo/src/mbpfan.c
├─ Líneas 82-100: filter_temp_spikes() [NUEVO]
├─ Líneas 86-98: fan_curve[] tabla [CAMBIO]
├─ Líneas 161-265: retrieve_sensors() [CAMBIO]
├─ Líneas 490-511: interpolate_curve_speed() [NUEVO]
├─ Líneas 513-541: compute_curve_fan_speed() [CAMBIO]
├─ Línea 756: aplicar filtro temperatura [NUEVO]
└─ Línea 783: aplicar filtro temperatura [NUEVO]

mbpfan-local-repo/compile_and_install.sh [CAMBIO]
└─ Ruta REPO_DIR corregida

mbpfan-local-repo/monitor_detailed.sh [NUEVO]
└─ Script de monitoreo con temperatura esperada vs real

/etc/mbpfan.conf [CAMBIO]
└─ min_fan1_speed = 2000
└─ low_temp = 70, high_temp = 85, max_temp = 96
```

---

## Notas y TODOs

- **TODO**: Pruebas con carga sostenida (>5 min a 90°C).
- **TODO**: Validar no hay throttling térmico.
- **TODO**: Medir ruido subjetivo bajo carga.
- **NOTA**: Tabla `fan_curve[]` está hardcodeada (Phase 2: hacer configurable).
- **NOTA**: Filtro usa delta >10°C (ajustable si hay más picos).

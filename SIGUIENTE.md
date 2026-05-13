# Próximo Paso — Pruebas con Carga

## Status Actual

✅ **Implementación v3 completada y instalada** (13 may 2026)

### Cambios implementados
- ✅ Filtro de sensores: SOLO coretemp Package id 0.
- ✅ Curva progresiva: interpolación lineal entre puntos.
- ✅ Filtro de picos: rechaza spikes >10°C hacia arriba.
- ✅ Compilado e instalado en `/usr/sbin/mbpfan`.

### Validación inicial (sin carga)
- ✅ Fan estable ~2100 RPM.
- ✅ Sin oscilaciones auditivas.
- ✅ Filtro rechaza picos de sensor correctamente.

---

## SIGUIENTE: Pruebas con Carga

Ejecutar pruebas bajo cargas reales para validar:
- Rampa correcta de fan según temperatura.
- Sin throttling térmico.
- Ruido aceptable.

### Prueba 1: Carga Ligera (15 minutos)

**Setup**:
```bash
# Terminal 1: Monitor
/home/gtx/Documentos/GITHUB/mbpfan_mod/mbpfan-local-repo/monitor_detailed.sh

# Terminal 2: Carga ligera
cd /home/gtx/Documentos/GITHUB/mbpfan_mod/mbpfan-local-repo
make clean && make -j2
```

**Esperado**:
- Temp: 75-82°C
- RPM: rampa de ~2100 a ~2600 RPM
- Fan: moderado (audible pero no agresivo)

**Checklist**:
- [ ] Sin picos falsos de RPM
- [ ] Rampa suave
- [ ] Temp no baja abruptamente (↓ del filtro permite)

---

### Prueba 2: Carga Media (15 minutos)

**Setup**:
```bash
# Compilación con más jobs
make -j4

# O stress-ng ligero
stress-ng --cpu 2 --timeout 15m --quiet
```

**Esperado**:
- Temp: 85-92°C
- RPM: ~3200-3900 RPM (rango agresivo)
- Fan: notable

**Checklist**:
- [ ] No hay saltos de RPM (histeresis funciona)
- [ ] Temp no oscila ±10°C
- [ ] No hay throttling (CPU freq mantiene >2.0 GHz)

---

### Prueba 3: Carga Fuerte (5 minutos)

**Setup**:
```bash
stress-ng --cpu 4 --timeout 5m --quiet
```

**Esperado**:
- Temp: 92-98°C
- RPM: 3900-5500 RPM (máximo)
- Fan: muy audible

**Checklist**:
- [ ] Temp no sube >100°C (evitar PROCHOT)
- [ ] CPU no throttlea
- [ ] Sin noise/lags en sistema

---

## Cómo Ejecutar

### Monitoreo en tiempo real

```bash
# Terminal 1: Monitor detallado
/home/gtx/Documentos/GITHUB/mbpfan_mod/mbpfan-local-repo/monitor_detailed.sh

# Terminal 2: Logs detallados
sudo journalctl -u mbpfan -f | grep "Curve Temp"

# Terminal 3: Carga
stress-ng --cpu 2 --timeout 15m --quiet
```

### Registro manual

Tomar screenshot o copiar output de monitor cada 3-5 minutos durante carga.

Ejemplo esperado durante carga media (85°C):
```
TEMP(C)  FAN_RPM  EXPECTED_RPM  DIFF      NOTES
==========================================
85      2800    2800         0         OK
86      2850    2883         -33       OK (dentro de ±250)
87      2900    2966         -66       OK
88      3050    3050         0         OK
...
```

---

## Criterios de Aceptación

Para considerar v3 **APROBADO**:

- [ ] Carga ligera: Temp <85°C, RPM suave, fan no agresivo.
- [ ] Carga media: Temp 85-92°C, RPM rampa correcta, fan moderado.
- [ ] Carga fuerte: Temp <100°C, CPU no throttlea, fan máximo.
- [ ] Sin oscilaciones audibles en ninguna carga.
- [ ] Sin saltos de RPM >250/ciclo (histeresis funciona).
- [ ] Sin picos falsos de temperatura (filtro funciona).

---

## Si hay problemas

### Problema: Fan no sube aunque CPU está caliente
**Causa probable**: Filtro rechazando cambios reales de temp.
**Solución**: Reducir delta de filtro (cambiar >10 a >15 en `filter_temp_spikes()`).

### Problema: Oscilaciones aún visibles
**Causa probable**: Histeresis insuficiente o delta de filtro muy alto.
**Solución**: Aumentar `max_rpm_drop_per_cycle` (línea 102 en mbpfan.c).

### Problema: CPU throttlea en carga
**Causa probable**: Temp límite demasiado bajo (max_temp = 96°C).
**Solución**: Aumentar en `/etc/mbpfan.conf`: `max_temp = 100` o subir curva.

### Debug rápido
```bash
# Ver temp real (sin filtro)
for i in {1..10}; do cat /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input; sleep 0.5; done | awk '{print $1/1000}'

# Ver RPM actual
cat /sys/devices/platform/applesmc.768/fan1_input

# Logs de mbpfan
sudo systemctl status mbpfan
sudo journalctl -u mbpfan -n 50 --no-pager
```

---

## Próxima Fase (después de validar v3)

Una vez validada v3 con cargas reales:

1. **Phase 2**: Hacer curva configurable (mover tabla de `.c` a `/etc/mbpfan.conf`).
2. **Phase 3**: Fork público con validación robusta.
3. **Phase 4**: Documentación de instalación/uso para usuarios.

Ver `PLAN.md` para más detalles.

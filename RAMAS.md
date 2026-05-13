# Estructura de Ramas — mbpfan Fork GOTXE

## Ramas Principales

### `main`
Rama base sincronizada con upstream oficial (linux-on-mac/mbpfan).
**Nunca modificar directamente.**

### `develop`
Rama de integración. Contiene v4 completa con todos los cambios.
Base para las ramas feature.

## Ramas Feature (por componente)

### `feature/temperature-sensor-filter`
**Problema**: Sensores fake (applesmc) reportaban -127°C, mbpfan leía máximo.

**Solución**:
- `retrieve_sensors()`: Lee SOLO coretemp Package id 0
- `filter_temp_spikes()`: Rate limiter +15°C/cycle
  - Rechaza spikes >15°C hacia arriba
  - Permite enfriamiento sin límite
  
**Líneas clave** (src/mbpfan.c):
- 82-100: `filter_temp_spikes()` función
- 161-265: `retrieve_sensors()` modificado
- 756, 783: Aplicación del filtro

**Testing**: Sin carga: 60-70°C sin oscilaciones

---

### `feature/progressive-fan-curve`
**Problema**: Thresholds fijos (low=63, high=66, max=86) causaban saltos de RPM.

**Solución**:
- Tabla hardcodeada 11 puntos (70°C@2100 → 100°C@6100)
- Interpolación lineal entre puntos
- Rampa suave, sin saltos audibles

**Líneas clave** (src/mbpfan.c):
- 86-98: Tabla `fan_curve[]`
- 490-511: `interpolate_curve_speed()` interpolación
- 541-569: `compute_curve_fan_speed()` aplicación

**Configuración** (mbpfan.conf):
- low_temp = 70 (ramp start)
- high_temp = 85 (aggressive zone)
- max_temp = 96 (máximo antes de crítica)

**Testing**: Carga media: 75-90°C progresivo, sin saltos

---

### `feature/fan-downramp-control`
**Problema**: Fan bajaba lentamente (-250 RPM/ciclo = 20 segundos).

**Solución**:
- Bajada dinámica: `(old_rpm - target_rpm) / 4`
- Ejemplo: 6100→2100 baja 1000 RPM/ciclo en 4 ciclos
- Responde naturalmente a enfriamiento real

**Líneas clave** (src/mbpfan.c):
- 564-571: Algoritmo downramp en `compute_curve_fan_speed()`

**Behavior**:
```
Ciclo 1: 105°C → 6100 RPM
Ciclo 2: 65°C  → 5100 RPM (baja 1000)
Ciclo 3: 65°C  → 4100 RPM (baja 1000)
Ciclo 4: 65°C  → 3100 RPM (baja 1000)
Ciclo 5: 65°C  → 2100 RPM (llega a target)
```

**Testing**: Sin carga después de stress: baja en 4-5 segundos

---

### `feature/monitoring-scripts`
**Scripts para validar comportamiento en vivo**.

**Scripts**:
- `monitor_detailed.sh`: Temp filtrada vs RPM esperado vs actual
- `monitor_realtime.sh`: Load, temp, fan cada 1 segundo

**Uso**:
```bash
./monitor_detailed.sh  # 30 ciclos, muestra diferencias
./monitor_realtime.sh  # Monitoreo continuo
```

**Testing**: Validación stress test, identificación de oscilaciones

---

### `feature/documentation`
**Documentación del mod y cambios**.

**Archivos**:
- `CAMBIOS.md`: Qué cambió, por qué, ejemplos
- `DATOS_TECNICOS.md`: Detalles implementación, fórmulas
- `ESTADO.md`: Validación, criterios aceptación
- `SIGUIENTE.md`: Pruebas pendientes, debug

**Para**:
- Usuarios: entender qué es el mod
- Desarrolladores: mantener, extender
- Reviewers: evaluar cambios

---

## Workflow

### Para probar una feature:
```bash
git checkout feature/temperature-sensor-filter
# ... hacer cambios ...
./compile_and_install.sh
./monitor_detailed.sh
```

### Para mergear a develop:
```bash
git checkout develop
git pull
git merge feature/temperature-sensor-filter --no-ff
git push origin develop
```

### Para sincronizar con upstream oficial:
```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

---

## Estado Actual

- ✅ v4 completa en `develop`
- ✅ Todas las features mergeadas en develop
- ✅ Documentación completa
- ⏳ Testing en stress completo
- ⏳ PR al upstream (opcional)

---

## Próximos Pasos

1. **Stress testing prolongado**: 30 minutos bajo carga
2. **Benchmark**: comparar vs networkException fork
3. **Refinamiento curva**: ajustar puntos si es necesario
4. **Tabla configurable**: mover curva a mbpfan.conf (v5)
5. **PR opcional**: proponer cambios al upstream oficial

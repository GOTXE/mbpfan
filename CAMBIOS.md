# Cambios Aplicados — Fase 2

## Problema Identificado

mbpfan leía **todos los sensores** del sistema (applesmc, pch, BAT0, coretemp), incluyendo valores inválidos:

```
TH0F:          -42.8°C    ← FALSO
THSP:         -127.0°C    ← FALSO
```

Función `get_temp()` tomaba el **máximo** de todos → si alguno reportaba 102°C falso, el fan se disparaba.

**Ejemplo real**:
- coretemp: 62°C ✓ (correcto)
- Sensor fantasma: 102°C ✗ (falso)
- mbpfan usa: 102°C → dispara fan a máximo
- Temperatura baja a 60°C por enfriamiento
- Ciclo repite: q q q q FFFFFFF q q q q FFFFF

## Solución

### Cambio 1: Filtrar sensores en `retrieve_sensors()`

**Archivo**: `mbpfan-local-repo/src/mbpfan.c` (líneas 161-265)

**Lo que cambió**:
- Antes: leer TODOS los sensores de ALL paths (`coretemp.*`, `applesmc`, `pch`, `BAT0`).
- Después: leer SOLO `coretemp.0` Package id 0 (temp1_input).

**Beneficio**:
- Package id 0 es el agregado de CPU (máximo de cores).
- Ignora sensores fake/inválidos.
- No reacciona a temp de batería o chipset.

**Código**:
```c
// Antes: int core = 0; for (core = 0; core < NUM_TEMP_INPUTS; core++) { ... }
// Después: path = smprintf("%s/temp1_input", hwmon_path);
```

Solo lee `temp1_input` (Package id 0), ignora el resto.

### Cambio 2: Curva progresiva con interpolación

**Archivo**: `mbpfan-local-repo/src/mbpfan.c` (líneas 86-98, 490-541)

**Lo que cambió**:
- Antes: thresholds fijos (low_temp, high_temp, max_temp) con rampa lineal entre ellos.
- Después: tabla hardcodeada `fan_curve[]` con puntos de control (70°C→2100 RPM, 75°C→2400 RPM, etc.).

**Función `interpolate_curve_speed()`**: interpola linealmente entre puntos.
**Función `compute_curve_fan_speed()`**: aplica la curva + histeresis de bajada.

**Beneficio**:
- Control fino: fan permanece en 2100 RPM hasta 70°C, luego rampa gradual.
- Sin oscilaciones: `max_rpm_drop_per_cycle = 250` limita bajadas bruscas.
- Quieto en idle: <70°C siempre 2100 RPM mínimo.

### Cambio 3: Filtro de picos de temperatura

**Archivo**: `mbpfan-local-repo/src/mbpfan.c` (líneas 82-100)

**Problema**: Sensor coretemp reporta picos ruidosos (60°C → 91°C → 65°C en 1-2 segundos).

**Solución**: Función `filter_temp_spikes()` rechaza subidas >10°C (picos ruidosos hacia arriba), permite bajadas sin límite (enfriamiento real).

```c
static unsigned short filter_temp_spikes(unsigned short new_temp)
{
    if (delta > 10) {  // Upward spike - REJECT
        return last_valid_temp;
    }
    last_valid_temp = new_temp;
    return new_temp;  // Downward or small change - ACCEPT
}
```

Se aplica en líneas 756 y 783 del loop principal.

**Beneficio**:
- Elimina oscilaciones por ruido del sensor.
- Fan mantiene RPM estable sin reaccionar a picos falsos.
- Permite enfriar normalmente cuando CPU realmente baja temp.

## Cómo compilar

```bash
cd ~/Documentos/GITHUB/mbpfan_mod/mbpfan-local-repo
make clean
make
sudo cp bin/mbpfan /usr/sbin/mbpfan
sudo systemctl restart mbpfan
```

## Validar cambios

```bash
# Ver que lee solo coretemp Package id 0
sudo journalctl -u mbpfan -f --no-pager | grep -i "Found\|sensor\|temp"

# Monitorear
watch -n 1 'sensors | grep "Core"; echo "---"; cat /sys/devices/platform/applesmc.768/fan1_output'

# Con verbose
sudo killall mbpfan
sudo /usr/sbin/mbpfan -v 2>&1 | head -20
```

## Esperado

- **Antes**: Fan se dispara a picos (q q q FFFFFFF) aunque temp esté en 60°C.
- **Después**: Fan sigue temp de coretemp correctamente (smooth).

## Archivos modificados

```
mbpfan-local-repo/src/mbpfan.c
└─ Función retrieve_sensors() (líneas 161-265)
   └─ Cambio: leer solo coretemp Package id 0, ignorar otros sensores
```

## Estado

- ✅ Código modificado.
- ⏳ Compilar + instalar.
- ⏳ Validar en sistema real.
- ⏳ Agregar histeresis si hay oscilaciones residuales.

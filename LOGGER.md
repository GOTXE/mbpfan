# Fan Logger — Continuous Monitoring

Monitor fan behavior over multiple days with automatic log rotation, compression, and analysis.

## Quick Start

### Manual (test):
```bash
./fan-logger.sh &
# Will log to logs/fan-YYYY-MM-DD.csv
# Ctrl+C to stop

# Analyze today's logs
./fan-analyze.sh
```

### Systemd (automatic, persistent):
```bash
# 1. Install service
sudo cp mbpfan-logger.service /etc/systemd/system/
sudo systemctl daemon-reload

# 2. Start logger
sudo systemctl start mbpfan-logger

# 3. Enable on boot
sudo systemctl enable mbpfan-logger

# 4. Check status
systemctl status mbpfan-logger
sudo journalctl -u mbpfan-logger -f
```

## Log Format

**File**: `logs/fan-YYYY-MM-DD.csv`

```
timestamp,temp_c,fan_rpm,expected_rpm,diff,status
2026-05-13T22:19:32+0200,73,2889,2800,89,OK
2026-05-13T22:19:33+0200,74,2900,2866,34,OK
2026-05-13T22:19:34+0200,75,2950,2933,17,OK
```

**Columns**:
- `timestamp`: ISO 8601 with timezone
- `temp_c`: CPU Package temperature (from coretemp)
- `fan_rpm`: Actual fan speed
- `expected_rpm`: Speed from curve (70°C→2100, 100°C→6100)
- `diff`: actual - expected (positive = too fast, negative = too slow)
- `status`: OK | TOO_HIGH | TOO_LOW (based on ±250 RPM tolerance)

## Analysis

### Today's logs:
```bash
./fan-analyze.sh
```

### Specific date:
```bash
./fan-analyze.sh 2026-05-12
```

### All logs (summary):
```bash
./fan-analyze.sh --all
```

### Example output:
```
═══════════════════════════════════════════════════════════
Fan Log Analysis — 2026-05-13
═══════════════════════════════════════════════════════════

📊 TEMPERATURE
  Current entries: 86400
  Min:  45°C
  Max:  105°C
  Avg:  68.3°C

🌀 FAN RPM (Actual)
  Min:  2000 RPM
  Max:  6100 RPM
  Avg:  2234 RPM

🎯 FAN RPM (Expected per curve)
  Min:  2100 RPM
  Max:  6100 RPM
  Avg:  2180 RPM

⚠️  STATUS SUMMARY
  OK:       86380 entries
  TOO_HIGH: 15 entries (fan >250 RPM above expected)
  TOO_LOW:  5 entries (fan >250 RPM below expected)

🔔 ANOMALIES
  Temp jumps (>10°C): 12

📈 PEAK EVENTS (Top 3 fan speeds)
  2026-05-13T17:32:45+0200 | Temp: 105°C, RPM: 6100 (expected: 6100, diff: 0)
  2026-05-13T17:32:44+0200 | Temp: 104°C, RPM: 6095 (expected: 6100, diff: -5)
  2026-05-13T17:32:43+0200 | Temp: 103°C, RPM: 6090 (expected: 6100, diff: -10)
```

## Log Rotation

### Automatic:
- Daily rotation at midnight
- Current day: `fan-2026-05-13.csv` (plain text, readable)
- Previous days: `fan-2026-05-12.csv.gz` (gzip compressed)

### Manual cleanup:
```bash
# Compress old logs
gzip logs/fan-2026-05-10.csv

# Delete very old logs (keep 30 days)
find logs/ -name "*.csv.gz" -mtime +30 -delete

# Check disk usage
du -sh logs/
```

## Interpreting Results

### Good behavior:
- Most entries: `OK` status
- Temp jumps: <20 over 24h
- TOO_HIGH/TOO_LOW: <1% of entries

### Problems:
- **High TOO_HIGH**: Fan slower than it should be (check throttling)
- **High TOO_LOW**: Fan faster than expected (may be good = protective)
- **Many temp jumps**: Sensor noise or actual fluctuations
- **Oscillations**: Temp rapidly up/down (filter not working)

## Curve Reference

Logger uses same curve as code (src/mbpfan.c fan_curve[]):

| Temp | Expected RPM |
|------|------------|
| <70°C | 2100 |
| 75°C | 2400 |
| 80°C | 2600 |
| 85°C | 2800 |
| 88°C | 3200 |
| 90°C | 3500 |
| 92°C | 3900 |
| 94°C | 4300 |
| 96°C | 4800 |
| 98°C | 5500 |
| 100°C | 6100 |

## Troubleshooting

### Logger not running:
```bash
systemctl status mbpfan-logger
sudo journalctl -u mbpfan-logger -n 50
```

### Logs not writing:
```bash
# Check permissions
ls -la logs/
# Should be readable by root

# Check free space
df -h logs/
```

### Analysis errors:
```bash
# Verify log format
head logs/fan-2026-05-13.csv

# Check for corruption
tail logs/fan-2026-05-13.csv
```

## Performance

- **CPU**: <0.1% (gawk + disk I/O)
- **Memory**: ~5MB
- **Disk**: ~300KB per day (uncompressed) → 30KB (gzip)
- **Daily logs**: 86,400 entries (1 second polling)
- **Monthly storage**: ~1MB (compressed)

## Notes

- Logger starts automatically if systemd service enabled
- Logs survive reboot (persistent storage)
- Old logs automatically compressed (saves 90% space)
- Analysis can run while logger is writing (safe)
- Data is append-only (no overwrites)

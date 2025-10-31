# windows/tools/kill_prev.ps1
# Intenta cerrar la app previa sin romper el exit code del build
try {
  Stop-Process -Name 'sansebas_stock' -Force -ErrorAction SilentlyContinue
} catch { }
Start-Sleep -Milliseconds 300
exit 0

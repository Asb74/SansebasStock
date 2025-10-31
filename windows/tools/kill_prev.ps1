# windows/tools/kill_prev.ps1
# Intenta cerrar la app previa sin romper el exit code del build
try {
  $p = Get-Process -Name 'sansebas_stock' -ErrorAction SilentlyContinue
  if ($p) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
} catch { }
Start-Sleep -Milliseconds 300
exit 0

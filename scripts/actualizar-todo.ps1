# Trae lo último de develop en cada repo (Git Flow: develop es la rama de integración).
# No toca repos con cambios sin guardar ni que estén en otra rama.
$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'repos.ps1')

$carpetas = @('.') + @($Repos.Keys)
foreach ($carpeta in $carpetas) {
    $ruta = Join-Path $raiz $carpeta
    if (-not (Test-Path (Join-Path $ruta '.git'))) { continue }
    $rama = git -C $ruta branch --show-current
    $cambios = git -C $ruta status --porcelain
    if ($rama -ne 'develop') {
        Write-Host "$carpeta : en la rama $rama, se omite"
    } elseif ($cambios) {
        Write-Host "$carpeta : tiene cambios sin guardar, se omite"
    } else {
        Write-Host "$carpeta : actualizando"
        git -C $ruta pull --ff-only
    }
}

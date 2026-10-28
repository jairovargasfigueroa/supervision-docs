# Clona cada proyecto en su carpeta dentro de la raíz. Los repos que todavía no existen se saltan.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'repos.ps1')

foreach ($carpeta in $Repos.Keys) {
    $destino = Join-Path $raiz $carpeta
    $url = "https://github.com/$Propietario/$($Repos[$carpeta]).git"
    if (Test-Path (Join-Path $destino '.git')) {
        Write-Host "Ya existe: $carpeta"
        continue
    }
    git ls-remote $url *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Todavía no existe en GitHub: $($Repos[$carpeta])"
        continue
    }
    Write-Host "Clonando $carpeta"
    git clone $url $destino
}

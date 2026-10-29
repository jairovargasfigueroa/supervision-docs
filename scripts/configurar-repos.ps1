# Configura cada repo de GitHub según docs/flujo-trabajo.md (Git Flow):
#   crea develop desde main y la deja como rama por defecto,
#   permite solo "merge commit" (PR normal, sin squash ni rebase), borra la rama al fusionar,
#   y protege main y develop (todo por PR, también el dueño; sin push directo, force push ni borrado).
# Aprobaciones requeridas: 0 mientras trabaje una sola persona. Cuando haya colaboradores, cambiar $Aprobaciones a 1.
# Requiere GitHub CLI con sesión del dueño de los repos. Se puede ejecutar varias veces (tarea 1.0).
# Los errores de gh se revisan con $LASTEXITCODE: en Windows PowerShell 5.1, 'Stop' corta el script con cualquier stderr.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'repos.ps1')
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$Aprobaciones = 0

# El cuerpo de la protección va en un archivo: pasarlo por tubería a gh en PowerShell 5.1 llega mal formado.
$archivoProteccion = Join-Path ([System.IO.Path]::GetTempPath()) 'proteccion-rama.json'
$proteccion = @{
    required_status_checks           = $null
    enforce_admins                   = $true
    required_pull_request_reviews    = @{ required_approving_review_count = $Aprobaciones; dismiss_stale_reviews = $true }
    restrictions                     = $null
    allow_force_pushes               = $false
    allow_deletions                  = $false
    required_conversation_resolution = $true
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($archivoProteccion, $proteccion, (New-Object System.Text.UTF8Encoding $false))

$fallidos = @()
$nombres = @('supervision-docs') + @($Repos.Values)
foreach ($nombre in $nombres) {
    $repo = "$Propietario/$nombre"
    & $gh api "repos/$repo" --silent 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "No existe: $repo"; continue }
    Write-Host "Configurando $repo"

    # develop desde main, si todavía no existe
    & $gh api "repos/$repo/branches/develop" --silent 2>$null
    if ($LASTEXITCODE -ne 0) {
        $shaMain = & $gh api "repos/$repo/git/ref/heads/main" --jq '.object.sha'
        & $gh api -X POST "repos/$repo/git/refs" -f ref='refs/heads/develop' -f sha=$shaMain --silent
        if ($LASTEXITCODE -ne 0) { $fallidos += "$repo (crear develop)"; continue }
    }

    & $gh repo edit $repo --default-branch develop --enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false --delete-branch-on-merge
    if ($LASTEXITCODE -ne 0) { $fallidos += "$repo (opciones)" }

    foreach ($rama in @('main', 'develop')) {
        & $gh api -X PUT "repos/$repo/branches/$rama/protection" --input $archivoProteccion --silent
        if ($LASTEXITCODE -ne 0) { $fallidos += "$repo (proteger $rama)" }
    }
}
Remove-Item $archivoProteccion

if ($fallidos.Count -gt 0) {
    Write-Host "Fallaron: $($fallidos -join ', ')"
    exit 1
}
Write-Host 'Listo'

# Configura cada repo de GitHub según docs/flujo-trabajo.md:
#   solo "squash and merge", borrar la rama al fusionar y proteger main
#   (PR obligatorio con 1 aprobación, sin push directo ni force push).
# Requiere GitHub CLI con sesión del dueño de los repos. Se ejecuta una vez por repo (tarea 1.0).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'repos.ps1')
$gh = 'C:\Program Files\GitHub CLI\gh.exe'

$nombres = @('supervision-docs') + @($Repos.Values)
foreach ($nombre in $nombres) {
    $repo = "$Propietario/$nombre"
    & $gh repo view $repo --json name *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "No existe: $repo"; continue }

    Write-Host "Configurando $repo"
    & $gh repo edit $repo --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false --delete-branch-on-merge

    $proteccion = @{
        required_status_checks        = $null
        enforce_admins                = $true
        required_pull_request_reviews = @{ required_approving_review_count = 1; dismiss_stale_reviews = $true }
        restrictions                  = $null
        allow_force_pushes            = $false
        allow_deletions               = $false
        required_conversation_resolution = $true
    } | ConvertTo-Json -Depth 5
    $proteccion | & $gh api -X PUT "repos/$repo/branches/main/protection" --input - | Out-Null
}

# Configura cada repo de GitHub según docs/flujo-trabajo.md (Git Flow):
#   crea develop desde main y la deja como rama por defecto,
#   permite solo "squash" y "merge commit", borra la rama al fusionar,
#   y protege main y develop (todo por PR, también el dueño; sin push directo, force push ni borrado).
# Aprobaciones requeridas: 0 mientras trabaje una sola persona. Cuando haya colaboradores, cambiar $Aprobaciones a 1.
# Requiere GitHub CLI con sesión del dueño de los repos. Se puede ejecutar varias veces (tarea 1.0).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'repos.ps1')
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$Aprobaciones = 0

$nombres = @('supervision-docs') + @($Repos.Values)
foreach ($nombre in $nombres) {
    $repo = "$Propietario/$nombre"
    & $gh repo view $repo --json name *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "No existe: $repo"; continue }
    Write-Host "Configurando $repo"

    # develop desde main, si todavía no existe
    & $gh api "repos/$repo/branches/develop" *> $null
    if ($LASTEXITCODE -ne 0) {
        $shaMain = & $gh api "repos/$repo/git/ref/heads/main" --jq '.object.sha'
        & $gh api -X POST "repos/$repo/git/refs" -f ref='refs/heads/develop' -f sha=$shaMain | Out-Null
    }

    & $gh repo edit $repo --default-branch develop --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false --delete-branch-on-merge

    $proteccion = @{
        required_status_checks           = $null
        enforce_admins                   = $true
        required_pull_request_reviews    = @{ required_approving_review_count = $Aprobaciones; dismiss_stale_reviews = $true }
        restrictions                     = $null
        allow_force_pushes               = $false
        allow_deletions                  = $false
        required_conversation_resolution = $true
    } | ConvertTo-Json -Depth 5
    foreach ($rama in @('main', 'develop')) {
        $proteccion | & $gh api -X PUT "repos/$repo/branches/$rama/protection" --input - | Out-Null
    }
}

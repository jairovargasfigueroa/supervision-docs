# Lista única de repos del proyecto: carpeta local -> nombre en GitHub.
# La usan clonar-todo.ps1, actualizar-todo.ps1 y configurar-repos.ps1.
$Propietario = 'jairovargasfigueroa'
$Repos = [ordered]@{
    'infra'                   = 'supervision-infra'
    'services/obras'          = 'supervision-ms-obras'
    'services/materiales'     = 'supervision-ms-materiales'
    'services/finanzas'       = 'supervision-ms-finanzas'
    'services/sincronizacion' = 'supervision-ms-sincronizacion'
    'services/ia'             = 'supervision-ms-ia'
    'services/notificaciones' = 'supervision-ms-notificaciones'
    'gateway'                 = 'supervision-gateway'
    'frontend/erp-shell'      = 'supervision-erp-shell'
    'frontend/mf-obras'       = 'supervision-mf-obras'
    'frontend/mf-materiales'  = 'supervision-mf-materiales'
    'frontend/mf-supervision' = 'supervision-mf-supervision'
    'frontend/portal'         = 'supervision-portal'
    'mobile/app-obra'         = 'supervision-app-obra'
}

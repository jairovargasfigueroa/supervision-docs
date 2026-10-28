# Preparar la máquina

Para quien se suma al equipo. Windows 11 (los comandos de PowerShell tienen su equivalente en Bash).

## 1. Instalar

| Herramienta | Versión | Para qué | Cómo comprobar |
|---|---|---|---|
| Git | 2.4x o más | repos | `git --version` |
| GitHub CLI | 2.x | crear PR, clonar | `gh --version` y `gh auth login` |
| nvm para Windows | 1.2 | cambiar de Node | `nvm version` |
| Node | **24 LTS** (`nvm install 24` y `nvm use 24`) | proyectos JavaScript | `node -v` → v24.x |
| Java (JDK) | **21** (Temurin u OpenJDK) | Obras | `java -version` |
| PHP + Composer | PHP **8.3 o más** (Laravel Herd trae 8.5) | Finanzas | `php -v` en PowerShell |
| Docker Desktop | con WSL 2 | `infra` | `docker compose version` |
| Python | **3.12** estable + `uv` | servicio IA (capas 3–5) | `python --version`, `uv --version` |
| Expo Go | en el celular Android | probar la app (sistema base) | — |
| Android Studio | solo para la *development build* (capa 3 y notificaciones) | — | — |
| Editor | VS Code o IntelliJ | — | — |

Configura git con tu nombre: `git config --global user.name "Tu Nombre"` y `git config --global user.email "tu-correo-de-github"`.

## 2. Clonar

```powershell
git clone https://github.com/jairovargasfigueroa/supervision-docs.git project-construccion
cd project-construccion
./scripts/clonar-todo.ps1      # clona cada proyecto en su carpeta (services/obras, gateway, frontend/..., mobile/..., infra)
```

La carpeta queda igual que en todas las máquinas; el `CLAUDE.md` de la raíz y `docs/` son los de este repo.

## 3. Primera vez

1. `infra`: copia `.env.example` a `.env` y ejecuta `./scripts/levantar.ps1` (agrega `-Perfil bases` si no tienes PostgreSQL ni MongoDB instalados).
2. En cada proyecto: copia su `.env.example` (Obras: `.env.properties.example`) y completa con los valores de `infra/.env`.
3. Instala dependencias: `npm install` (JavaScript), `composer install` (Finanzas), `./mvnw -q -DskipTests package` (Obras, descarga dependencias).
4. Levanta todo en el orden de `docs/entorno-local.md`.
5. Comprueba con `infra/scripts/estado.ps1`: todo en «sano».
6. Abre `http://localhost:4200` e inicia sesión con `admin1` / `Prueba123!`.

## 4. Antes de empezar a trabajar cada día

```powershell
./scripts/actualizar-todo.ps1   # git pull en main de cada repo (no toca ramas con cambios)
```

Luego sigue `docs/flujo-trabajo.md`: toma una funcionalidad del plan, crea la rama y abre el PR en borrador.

## Trabajar con el agente (Claude)

Abre Claude en la carpeta raíz y pídele: «Lee el CLAUDE.md y sigue con la funcionalidad NNN». El agente crea las ramas, implementa tarea por tarea, hace los commits a tu nombre y abre los PR; tú revisas y pides la revisión a otra persona.

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
| Python | **3.12** estable, gestionado por `uv` | servicio IA (capa 4; luego 3 y 5) | `uv --version` y `uv python find 3.12` |
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

1. `infra`: copia `.env.example` a `.env` y ejecuta `./scripts/levantar.ps1` (levanta RabbitMQ, Keycloak y DynamoDB Local; agrega `-Perfil bases` si no tienes PostgreSQL ni MongoDB instalados).
2. En cada proyecto: copia su `.env.example` (Obras: `.env.properties.example`) y completa con los valores de `infra/.env`.
3. Instala dependencias: `npm install` (JavaScript), `composer install` (Finanzas), `./mvnw -q -DskipTests package` (Obras, descarga dependencias) y `uv sync` (IA).
   - **IA (capa 4):** instala `uv` (por ejemplo `py -3.12 -m pip install --user uv` y agrega su carpeta `Scripts` al `PATH`), luego `uv python install 3.12` (una versión preliminar como 3.12.0rc2 no sirve) y, en `services/ia`, `uv sync`. Detalle y el arreglo de un error conocido de `uv python install` en Windows: `services/ia/README.md`.
   - **Base de reportes (401):** si usas tu PostgreSQL instalado, crea una vez como `postgres` el usuario `ia` y la base `reportes_db` (`docs/entorno-local.md`); con el perfil `bases` la crea el contenedor. Luego, en `services/ia`, `uv run alembic upgrade head`.
4. Levanta todo en el orden de `docs/entorno-local.md` (IA con `uv run ia-api` y `uv run ia-worker`, o en contenedor con `docker compose --profile ia up -d --build` en `infra`). Con los datos de prueba cargados, corre una vez la carga inicial de la base de reportes (`uv run ia-carga-inicial`).
5. Comprueba con `infra/scripts/estado.ps1`: todo en «sano».
6. Abre `http://localhost:4200` e inicia sesión con `admin1` / `Prueba123!`.

## 4. Antes de empezar a trabajar cada día

```powershell
./scripts/actualizar-todo.ps1   # git pull en develop de cada repo (no toca ramas con cambios)
```

Luego sigue `docs/flujo-trabajo.md`: toma una funcionalidad del plan, crea la rama y abre el PR en borrador.

## Trabajar con el agente (Claude)

Abre Claude en la carpeta raíz y pídele: «Lee el CLAUDE.md y sigue con la funcionalidad NNN». El agente crea las ramas, implementa tarea por tarea, hace los commits a tu nombre y abre los PR; tú revisas y pides la revisión a otra persona.

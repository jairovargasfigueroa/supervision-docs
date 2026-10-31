# Puntos del ingeniero y dónde se aplican

Fuente: lo que el ingeniero pidió en clase (audio y transcripción). Condiciones generales: es una **plataforma**; el tamaño lo decide el equipo; cada punto debe aplicarse con pertinencia; metodología ICONIX para el documento.

| N.º | Punto | Dónde | Cómo | Proyecto | Etapa |
|---|---|---|---|---|---|
| 1 | Microservicios (mínimo 3: Spring Boot, NestJS, Laravel) | Backend | Obras (Spring Boot), Materiales (NestJS), Finanzas (Laravel); extra: IA (FastAPI) y Sincronización (NestJS) | `services/*` | Base |
| 2 | Microfrontends con shell | ERP | Shell Angular con Native Federation; microfrontends Obras (Angular), Materiales (React) y Supervisión (React) | `frontend/*` | Base |
| 3 | Frontend: Angular y React obligatorios (tercero opcional) | Las 3 aplicaciones | Angular en el shell y en Obras; React en Materiales, Supervisión y el portal; React Native en la app. Vue solo si el equipo decide agregarlo | `frontend/*`, `mobile/*` | Base |
| 4 | GraphQL solo en el ERP; REST en lo demás | ERP → gateway | Toda la interacción del ERP por el gateway GraphQL; portal, app y servicios por REST | `gateway` | Base |
| 5 | Agentes en el ERP (funcionalidades con misión y esquemas de reporte) | ERP | Seguimiento de obras, Control de materiales y Control de cobros: revisan solos, reportan, sugieren y una persona aprueba | `services/ia`, `frontend/mf-supervision` | Capa 5 |
| 6 | IA local en el móvil y en el navegador | App y ERP | App: casco y chaleco en la foto. Navegador: voz a texto y rostros difuminados (opcional desde el 31/10/2026) | `mobile/app-obra`, `frontend/*` | Capa 3 |
| 7 | Offline en móvil y web (PWA) | App y ERP | App: registros de campo sin señal. ERP: PWA para consultar lo guardado y el borrador de planilla | `mobile/app-obra`, `frontend/erp-shell` | Capa 1 |
| 8 | Sincronización con idempotencia | Sincronización | Identificador creado en el celular; DynamoDB «guardar solo si no existe»; TTL de 30 días | `services/sincronizacion` | Capa 1 |
| 9 | Funcionar con mala conexión | App, ERP, servicios | Datos livianos primero, fotos comprimidas y por partes, reintentos con espera creciente, tiempos máximos en el gateway | varios | Capa 1 |
| 10 | Transacción entre 3 microservicios (Saga) | Aprobar planilla | Obras bloquea → Finanzas reserva saldo → Materiales cierra consumos → Finanzas emite cobro → Obras aprueba; compensación en orden inverso | `services/obras`, `finanzas`, `materiales` | Base |
| 11 | ML supervisado y no supervisado | IA → tablero y agentes | Riesgo de retraso (supervisado, XGBoost, 402); salidas de material raras (no supervisado, Isolation Forest, 403). Los dos se entrenan con datos sintéticos (script reproducible que tarda segundos, sin GPU) y se pueden reentrenar con datos reales | `services/ia` | Capa 4 |
| 12 | Deep learning con TensorFlow (imágenes) | Foto de avance | Detector de casco y chaleco entrenado con TensorFlow, convertido a TensorFlow Lite | `mobile/app-obra`, `services/ia` | Capa 3 |
| 13 | Automatización entre microservicios (n8n sugerido) | Materiales → Finanzas → correo | Stock bajo → orden de compra → correo al proveedor → ingreso → cuenta por pagar | n8n, `services/materiales`, `finanzas` | Capa 2 |
| 14 | Reportes generativos por voz, en pantalla y exportables a Excel | ERP (Supervisión) | Voz → texto en el navegador → intención validada → el código calcula → la IA redacta → tabla y exportar a Excel | `services/ia`, `frontend/mf-supervision` | Capa 5 |
| 15 | MCP | Cada microservicio → agentes | Cada servicio publica herramientas MCP de solo lectura; los agentes las descubren y llaman | `services/*` | Capa 5 |
| 16 | Seguridad (inyección SQL e instrucciones) | Agentes y reportes | La IA no escribe SQL; reportes de una lista permitida; lo leído se trata como dato; aprobación humana | `services/ia` | Capa 5 |
| 17 | Bases de datos: relacional, MongoDB, DynamoDB | Cada servicio | PostgreSQL (Obras, Finanzas, reportes); MongoDB (catálogo de materiales, informes de agentes); DynamoDB (sincronización) | `services/*` | Base y capa 1 |
| 18 | Acceso único (SSO) para varias aplicaciones | Las 3 aplicaciones | Keycloak con roles; menú para pasar de una aplicación a otra sin volver a iniciar sesión | infraestructura y frontends | Base |
| 19 | Arquitectura del código: DDD, Hexagonal, Clean | Microservicios | DDD por área y en la planilla; Hexagonal en Obras y Finanzas; Clean en Materiales | `services/*` | Base |
| 20 | Arquitectura en 4 niveles (backend, frontend, datos, despliegue); para los reportes que cruzan servicios, «algún mecanismo» (no pidió un microservicio) | Toda la plataforma | Datos: una base por servicio y, como mecanismo para lo que cruza servicios, **CQRS: modelo de lectura alimentado por eventos** (`reportes_db`, dentro del servicio de IA; cada servicio sigue escribiendo y leyendo lo suyo; sin *event sourcing*; carga inicial una vez por REST). Despliegue en contenedores | todos (`services/ia` para el modelo de lectura) | Base y capa 4 |
| — | Despliegue en 3 nubes | Despliegue | AWS (Sincronización + DynamoDB), Google Cloud (IA y Materiales), Azure (Obras, Finanzas, gateway, Keycloak, apps web). Reparto propuesto | todos | Capa 6 |

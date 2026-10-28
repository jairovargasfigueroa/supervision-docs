# 601 · Contenedores y CI/CD · tareas de `services/sincronizacion`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Requiere el proyecto de la 101. Cuando exista, este archivo se copia a `services/sincronizacion/docs/specs/601-contenedores-ci/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Clientes de DynamoDB y S3 sin credenciales explícitas cuando `AWS_ACCESS_KEY_ID` o `SINC_S3_ACCESS_KEY` están vacías (cadena de credenciales del AWS SDK: rol de Lambda) y sin *endpoint* cuando `DYNAMODB_ENDPOINT` o `SINC_S3_ENDPOINT` están vacíos; *path-style* solo con *endpoint* propio (RustFS)
- [ ] `Dockerfile` (`node:24-alpine` en dos etapas, usuario `node`) con `COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0 /lambda-adapter /opt/extensions/lambda-adapter`; comprobar que la imagen corre igual con `docker run`
- [ ] `.github/workflows/ci-cd.yml`: pruebas con DynamoDB Local y RustFS de servicio, imagen en ECR, `aws lambda update-function-code` con el rol OIDC y espera a que termine la actualización
- [ ] Prueba después del despliegue: `/salud` por la URL de la función y subida de una parte binaria (`PUT /subidas/{id}/partes/0`) que se refleja en `GET /subidas/{id}`

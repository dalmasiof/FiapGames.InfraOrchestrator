# Matriz ConfigMap x Secret

## Auth

| Chave | Fonte alvo |
| --- | --- |
| ASPNETCORE_ENVIRONMENT | ConfigMap |
| ASPNETCORE_URLS | ConfigMap |
| Jwt__Issuer | ConfigMap |
| Jwt__Audience | ConfigMap |
| RabbitMq__HostName | ConfigMap |
| RabbitMq__Port | ConfigMap |
| ConnectionStrings__FIAPGamesConnection | Secret |
| Jwt__Key | Secret |
| RabbitMq__UserName | Secret |
| RabbitMq__Password | Secret |

## Catalog

| Chave | Fonte alvo |
| --- | --- |
| ASPNETCORE_ENVIRONMENT | ConfigMap |
| ASPNETCORE_URLS | ConfigMap |
| Jwt__Issuer | ConfigMap |
| Jwt__Audience | ConfigMap |
| RabbitMq__HostName | ConfigMap |
| RabbitMq__Port | ConfigMap |
| ConnectionStrings__FIAPGamesConnection | Secret |
| Jwt__Key | Secret |
| RabbitMq__UserName | Secret |
| RabbitMq__Password | Secret |

## Payment

| Chave | Fonte alvo |
| --- | --- |
| ASPNETCORE_ENVIRONMENT | ConfigMap |
| ASPNETCORE_URLS | ConfigMap |
| RabbitMq__HostName | ConfigMap |
| RabbitMq__Port | ConfigMap |
| ConnectionStrings__FIAPGamesConnection | Secret |
| RabbitMq__UserName | Secret |
| RabbitMq__Password | Secret |

## Notification

| Chave | Fonte alvo |
| --- | --- |
| ASPNETCORE_ENVIRONMENT | ConfigMap |
| RabbitMq__HostName | ConfigMap |
| RabbitMq__Port | ConfigMap |
| ConnectionStrings__DefaultConnection | Secret |
| RabbitMq__UserName | Secret |
| RabbitMq__Password | Secret |

## Infra compartilhada

| Chave | Fonte alvo |
| --- | --- |
| ACCEPT_EULA | ConfigMap |
| MSSQL_SA_PASSWORD | Secret |
| RABBITMQ_DEFAULT_USER | ConfigMap |
| RABBITMQ_DEFAULT_PASS | Secret |

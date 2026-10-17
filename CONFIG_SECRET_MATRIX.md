# Configuration and secret matrix

Production secrets are stored in Azure Key Vault and consumed with the user-assigned managed identity `id-fiapgames-workloads-prod`. They must not be committed to Git or stored in application settings as plain text.

## Azure Key Vault

| Secret | Consumer | Purpose |
| --- | --- | --- |
| `ConnectionStrings--AuthConnection` | Auth API | Auth database connection |
| `ConnectionStrings--CatalogConnection` | Catalog API | Catalog database connection |
| `ConnectionStrings--PaymentConnection` | Payment API | Payment database connection |
| `ConnectionStrings--NotificationConnection` | Notification Function | Notification database connection |
| `MongoDb--ConnectionString` | Notification Function | Cosmos DB Mongo API connection |
| `MongoDb--DatabaseName` | Notification Function | Mongo database name |
| `Redis--ConnectionString` | Catalog API | Distributed cache connection |
| `Jwt--PrivateKey` | Auth API | PKCS#8 RSA private key used for RS256 signing |
| `Jwt--Authority` | Payment API | Auth OpenID discovery endpoint |
| `Elasticsearch--Endpoint` | Catalog API | Managed search endpoint; provision/configure only after cost approval |
| `Elasticsearch--ApiKey` | Catalog API | Managed search API key |
| `RabbitMq--UserName` | APIs | RabbitMQ credential |
| `RabbitMq--Password` | APIs | RabbitMQ credential |

The public RSA key is published by Auth as JWKS. Catalog, Payment and APIM validate tokens through that endpoint; they do not receive the private key.

## GitHub Actions

| Name | Type | Purpose |
| --- | --- | --- |
| `AZURE_CREDENTIALS` | Repository secret | Azure login JSON for the deployment service principal |
| `ACR_USERNAME` | Repository secret | ACR push and migration-job pull |
| `ACR_PASSWORD` | Repository secret | ACR push and migration-job pull |
| `RABBITMQ_USERNAME` | Auth repository secret | AKS RabbitMQ Secret creation at deploy time |
| `RABBITMQ_PASSWORD` | Auth repository secret | AKS RabbitMQ Secret creation at deploy time |
| `RABBITMQ_USERNAME` | Auth repository secret | Creates the AKS RabbitMQ Kubernetes Secret at deploy time |
| `RABBITMQ_PASSWORD` | Auth repository secret | Creates the AKS RabbitMQ Kubernetes Secret at deploy time |
| `KEY_VAULT_URI` | Repository variable | Key Vault URI |
| `AZURE_MANAGED_IDENTITY_RESOURCE_ID` | Repository variable | Workload identity resource ID |
| `AZURE_MANAGED_IDENTITY_CLIENT_ID` | Repository variable | Workload identity client ID |

Use the exact names expected by each workflow. Never print secret values in workflow logs.

## Local development

Copy `.env.example` to `.env` and keep `.env` and all PEM files untracked. The local Compose environment mounts `jwt-private.pem` as a Docker secret.

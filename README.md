# FIAP Cloud Games - Infrastructure Orchestrator

Central guide for the FCG platform. This repository provisions the shared Azure infrastructure, documents the deployment order and provides the local development environment.

## Architecture

| Area | Technology | Responsibility |
| --- | --- | --- |
| Runtime | .NET 10, Azure Container Apps | Auth, Catalog and Payment APIs |
| Gateway | Azure API Management Developer | Only public entry point, routing, CORS, JWT validation and rate limiting |
| Serverless | Azure Functions .NET isolated | Authentication and payment notifications |
| Messaging | RabbitMQ and Azure Service Bus | API messaging and serverless notification triggers |
| Data | Azure SQL | One database per service |
| Security | Key Vault, Managed Identity, RSA/JWKS | Secrets and asymmetric JWT signing/validation |
| Images | Azure Container Registry Basic | Versioned service images |
| Observability | Log Analytics and Application Insights | Centralized platform and Function logs |
| IaC and CI/CD | Terraform and GitHub Actions | Repeatable provisioning, migrations and deployments |

Production request flow:

```text
Client -> API Management -> Auth / Catalog / Payment Container Apps
                              |
                              +-> RabbitMQ
Auth / Payment -> Service Bus queues -> Notification Azure Functions -> Azure SQL
```

The Container Apps reject direct Internet traffic through IP restrictions. Clients must use:

```text
https://apim-fiapgames-prod-64f434dd-v2.azure-api.net
```

## Repository layout

```text
main.tf                         Shared Azure infrastructure
terraform.tfvars.example       Safe Terraform variable template
policies/                       APIM policies and OpenAPI contracts
postman/                        Current gateway test collection
scripts/generate-jwt-keys.ps1   RSA key generation
scripts/run-migration-job.ps1   Manual ephemeral migration job
scripts/suspend-environment.ps1 Cost-saving shutdown
scripts/resume-environment.ps1  Environment startup
docker-compose.yml              Local Auth/Catalog/Payment environment
```

The serverless Notification infrastructure intentionally lives in the `FiapGames.Notification/infra` directory of its own repository. Kubernetes manifests and the old continuously running notification worker are no longer part of the supported architecture.

## Prerequisites

- Azure CLI authenticated with access to the target subscription
- Terraform `~> 3.90` (the current workstation uses `C:\terraform\terraform.exe`)
- Docker Desktop for local execution
- .NET 10 SDK for service development
- OpenSSL to generate the JWT signing key
- Azure Functions Core Tools for local Notification execution

Register the required Azure resource providers once per subscription:

```powershell
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.ServiceBus
az provider register --namespace Microsoft.Web
```

Wait until each provider reports `Registered` before applying Terraform.

## Provision the shared environment

1. Select the intended subscription.

```powershell
az login
az account set --subscription "<subscription-id>"
az account show --query "{name:name,id:id,tenantId:tenantId}" --output table
```

2. Create a local variables file. It is ignored by Git.

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Set strong values for the SQL and RabbitMQ credentials and valid APIM publisher data. Do not commit this file.

3. Initialize and validate Terraform.

```powershell
C:\terraform\terraform.exe init
C:\terraform\terraform.exe fmt -check
C:\terraform\terraform.exe validate
C:\terraform\terraform.exe plan -out local.tfplan
```

4. Review the plan and apply it.

```powershell
C:\terraform\terraform.exe apply local.tfplan
```

The shared stack creates resource group `rg-fiapgames-prod`, ACR, Key Vault, user-assigned managed identity, Azure SQL databases, Log Analytics, Container Apps Environment, RabbitMQ and APIM. Terraform outputs the gateway URL, Key Vault URI, ACR login server and identity identifiers.

5. Generate and upload the RSA private key.

```powershell
.\scripts\generate-jwt-keys.ps1
az keyvault secret set `
  --vault-name kv-fiapgames-64f434dd `
  --name Jwt--PrivateKey `
  --file jwt-private.pem
```

The PEM files are ignored by Git. Never commit or print the private key.

6. Provision the serverless Notification resources from its repository.

```powershell
Set-Location ..\FiapGames.Notification\infra
C:\terraform\terraform.exe init
C:\terraform\terraform.exe validate
C:\terraform\terraform.exe plan -out local.tfplan
C:\terraform\terraform.exe apply local.tfplan
```

That stack creates Azure Service Bus queues, Function App, Storage, Application Insights and the required RBAC assignments.

## Deploy the applications

Each application repository owns its workflow:

| Repository | Production branch | Workload |
| --- | --- | --- |
| `FiapGame.AuthService` | `main` | `ca-auth-api` |
| `FiapGames.Catalog` | `master` | `ca-catalog-api` |
| `FiapGame.PaymentService` | `main` | `ca-payment-api` |
| `FiapGames.Notification` | `master` | `func-fcg-notify-64f434dd` |

For the APIs, a push builds and pushes an image tagged with the commit SHA, executes an ephemeral Container Apps Job with `--migrate`, and updates the Container App only after a successful migration. Notification applies its own Terraform, migrates its database and performs a Function ZIP deployment.

Configure the repository secrets and variables listed in [CONFIG_SECRET_MATRIX.md](CONFIG_SECRET_MATRIX.md) before the first run. The deployment service principal should have only the roles and resource-group scope required by the workflows.

## Local development

The supported local Compose profile runs SQL Server, RabbitMQ, Auth, Catalog and Payment. Notification is serverless and should be started separately with Azure Functions Core Tools.

```powershell
Copy-Item .env.example .env
.\scripts\generate-jwt-keys.ps1
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

Local endpoints:

| Service | URL |
| --- | --- |
| Auth | `http://localhost:8081` |
| Catalog | `http://localhost:8082` |
| Payment | `http://localhost:8083` |
| RabbitMQ management | `http://localhost:15672` |

Stop the local stack with `docker compose down`. Add `-v` only when intentionally discarding local database data.

## Validation

Import [FCG-Azure.postman_collection.json](postman/FCG-Azure.postman_collection.json) in Postman. Execute the login request first; it stores the JWT for the protected Catalog and Payment calls.

Expected security checks:

- APIM login returns a JWT signed with RS256.
- The JWKS endpoint publishes only the RSA public key.
- Protected requests without a token return `401`.
- Protected requests with the login token reach the correct API.
- Direct Container App access returns `403` because only APIM is allowed.
- A published authentication or payment event triggers the corresponding Azure Function.
- Application Insights shows the Function invocation and persistence logs.

Useful health endpoints behind each service are `/health/live` and `/health/ready`.

## Cost control

The environment can be suspended without deleting resources:

```powershell
.\scripts\suspend-environment.ps1
```

Resume it before demos or integration tests:

```powershell
.\scripts\resume-environment.ps1
```

The scripts scale/deactivate Container Apps, stop/start the Function and change SQL databases between provisioned Basic and serverless auto-pause modes. APIM Developer, ACR, Key Vault, Storage and Log Analytics remain provisioned and can still generate residual cost. Do not run `terraform apply` while intentionally suspended, because Terraform may restore the declared running state.

## Repository hygiene

Generated plans, Terraform state, provider caches, `.env`, PEM keys and build output must remain untracked. Before delivery:

```powershell
git status --short
git ls-files | Select-String -Pattern '\.(pem|tfstate|tfplan)$'
C:\terraform\terraform.exe fmt -check main.tf
C:\terraform\terraform.exe validate
```

`git status --short` must return no output after the intended changes are committed.

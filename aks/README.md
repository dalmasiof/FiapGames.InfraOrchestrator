# FCG AKS demo stack

This isolated Terraform root manages the AKS cluster, ACR pull permission, workload identity federation, and the Catalog Redis cache. It references the existing resource group, ACR, Key Vault, and user assigned identity; it does not use or modify the legacy root Terraform state.

Terraform state is local in `terraform.tfstate` and ignored by Git. Keep a protected backup of that file: it contains sensitive infrastructure data and is required to manage the resources. `terraform.tfvars` is also local and ignored.

## Current Azure state

Validated in subscription `64f434dd-5cb0-4c01-971d-7e0e6ba4db9b`, Brazil South, on 2026-11-02 after running `resume-environment.ps1`:

- AKS `aks-fiapgames-prod` is running with one `Standard_D2_v4` node in `Ready` state.
- Redis Basic C0 and its `Redis--ConnectionString` Key Vault secret are provisioned.
- Auth and Catalog deployments are healthy at `4.228.73.111:8081` and `74.163.192.65:8082`; both migration Jobs completed. Use these LoadBalancer endpoints for the AKS demo because APIM still targets legacy Container Apps.
- The Notification Function is running, and both Service Bus triggers are present. Cosmos DB Mongo account, database, collection and Key Vault connection secret exist.
- The Elastic Cloud endpoint in Key Vault does not resolve, and no Elastic resource exists in the Azure subscription. Catalog fuzzy search is unavailable until the external Elastic project is restored and its endpoint/API key are updated.
- SQL databases are online with serverless auto-pause set to 60 minutes; storage remains billable when compute pauses.
- API Management Developer, ACR, Key Vault, Storage, Log Analytics, AKS disks/outbound IP and the Elastic Marketplace service may still incur charges.
- The existing API Management Developer service, Basic ACR, and AKS outbound public IP remain. APIM has no stop operation for this SKU; deleting it would remove its gateway configuration. ACR and the outbound IP also retain service charges.

The live validation exercised Auth login, Catalog reads and Redis cache writes, Catalog fuzzy search through Elasticsearch, RabbitMQ connectivity, and an Auth notification processed by the Function and persisted to MongoDB. Temporary search data and the temporary test user/history record were removed.

## Start the demo

From the repository root, use the lifecycle script:

```powershell
.\scripts\resume-environment.ps1
```

The script requires Azure CLI, Terraform, kubectl and .NET 10 SDK. Authenticate with `az login`; ensure the local `terraform.tfstate` is present; and recreate the Elastic project with Key Vault secrets `Elasticsearch--Endpoint`, `Elasticsearch--ApiKey` and `Elasticsearch--Index`. It validates the Elasticsearch search endpoint before making Azure changes. Then it tests local Auth/Catalog source, builds and pushes uniquely tagged images to ACR, plans and applies only non-destructive Terraform changes, starts AKS, creates the RabbitMQ Kubernetes Secret from Key Vault, applies the RabbitMQ manifests, runs database migration Jobs, deploys the APIs, waits for readiness, and starts the Notification Function. Local uncommitted code is what gets built; GitHub CLI and workflow secrets are not required for this lifecycle.

Use the external IPs printed by the script to reach the AKS services. APIM currently targets the legacy Container Apps backend and is not updated by this script.

## Stop after a demo

```powershell
.\scripts\suspend-environment.ps1
```

The script removes the AKS API LoadBalancer Services, scales the API deployments down, stops AKS and the Notification Function, deactivates legacy Container Apps, deletes the disposable Redis cache, and configures SQL databases to auto-pause after 15 minutes of inactivity. RabbitMQ data and the Terraform state are preserved. On the next resume, Terraform recreates Redis and the script rebuilds and deploys local source, recreating the Services.

Elastic Serverless is managed outside the Terraform state and cannot be removed by these scripts; delete it through the provider when it is not needed. APIM Developer, ACR, Key Vault, Storage, Log Analytics, SQL storage, AKS disks/outbound IP and Elastic Cloud may continue to incur costs. This lifecycle reduces spend but does not guarantee zero cost.

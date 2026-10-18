# FCG AKS demo stack

This isolated Terraform root manages the AKS cluster, ACR pull permission, workload identity federation, and the Catalog Redis cache. It references the existing resource group, ACR, Key Vault, and user assigned identity; it does not use or modify the legacy root Terraform state.

Terraform state is local in `terraform.tfstate` and ignored by Git. Keep a protected backup of that file: it contains sensitive infrastructure data and is required to manage the resources. `terraform.tfvars` is also local and ignored.

## Current Azure state

Validated in subscription `64f434dd-5cb0-4c01-971d-7e0e6ba4db9b`, Brazil South, on 2026-10-17:

- AKS `aks-fiapgames-prod` is stopped. Its single `Standard_D2_v4` node is deallocated.
- Redis and its Key Vault connection secret were deleted after testing to avoid continuous cache charges. Terraform will recreate them on apply.
- The Elastic Serverless resource was deleted after testing. It is not managed by this Terraform root and must be recreated separately before Catalog search can run again.
- The Auth and Catalog LoadBalancer Services were deleted to release their public frontend IPs. Applying the service manifests or running the GitHub workflows creates new IPs.
- The Notification Function is stopped. Container App replicas are at zero; Prometheus and Grafana revisions are deactivated.
- SQL databases use serverless auto-pause. The lifecycle scripts set the delay to 60 minutes while resumed and 15 minutes while suspended; storage remains billable when compute is paused.
- The existing API Management Developer service, Basic ACR, and AKS outbound public IP remain. APIM has no stop operation for this SKU; deleting it would remove its gateway configuration. ACR and the outbound IP also retain service charges.

The live validation exercised Auth login, Catalog reads and Redis cache writes, Catalog fuzzy search through Elasticsearch, RabbitMQ connectivity, and an Auth notification processed by the Function and persisted to MongoDB. Temporary search data and the temporary test user/history record were removed.

## Start the demo

From the repository root, use the lifecycle script:

```powershell
.\scripts\resume-environment.ps1
```

The script requires Azure CLI, Terraform, kubectl and .NET 10 SDK. Authenticate with `az login`; ensure the local `terraform.tfstate` is present; and recreate the Elastic project with Key Vault secrets `Elasticsearch--Endpoint` and `Elasticsearch--ApiKey`. The script tests local Auth/Catalog source, builds and pushes uniquely tagged images to ACR, plans and applies only non-destructive Terraform changes, starts AKS, creates the RabbitMQ Kubernetes Secret from Key Vault, applies the RabbitMQ manifests, runs database migration Jobs, deploys the APIs, waits for readiness, and starts the Notification Function. Local uncommitted code is what gets built; GitHub CLI and workflow secrets are not required for this lifecycle.

Use the external IPs printed by the script to reach the AKS services. APIM currently targets the legacy Container Apps backend and is not updated by this script.

## Stop after a demo

```powershell
.\scripts\suspend-environment.ps1
```

The script removes the AKS API LoadBalancer Services, scales the API deployments down, stops AKS and the Notification Function, deactivates legacy Container Apps, deletes the disposable Redis cache, and configures SQL databases to auto-pause after 15 minutes of inactivity. RabbitMQ data and the Terraform state are preserved. On the next resume, Terraform recreates Redis and the script rebuilds and deploys local source, recreating the Services.

Elastic Serverless is managed outside the Terraform state and cannot be removed by these scripts; delete it through the provider when it is not needed. APIM Developer, ACR, Key Vault, Storage, Log Analytics, SQL storage, AKS disks/outbound IP and Elastic Cloud may continue to incur costs. This lifecycle reduces spend but does not guarantee zero cost.

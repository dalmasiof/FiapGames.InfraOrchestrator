# Isolated AKS demo stack

This root manages only the FCG demo AKS cluster and its ACR/Workload Identity assignments. It references the existing resource group, ACR and user-assigned identity. It does not load the legacy root state, so it cannot delete the 44 resources tracked there.

The remote Terraform state storage account is currently inaccessible. This root therefore supports local validation and a read-only preflight plan only. Do not run `terraform apply` until a durable remote backend is approved and configured.

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init -backend=false
terraform fmt -check
terraform validate
terraform plan -input=false -out=aks-demo.tfplan
```

The cluster uses the AKS Free management tier and one `Standard_B2s` node. The node, disk and public IP are billable. Confirm current quota and monthly cost against the approved budget before applying. Do not apply this stack as part of routine validation.
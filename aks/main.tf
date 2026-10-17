terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  description = "Azure subscription for the isolated FCG AKS demo stack."
  type        = string
}

variable "location" {
  description = "Azure region for the demo cluster."
  type        = string
  default     = "brazilsouth"
}

variable "resource_group_name" {
  type    = string
  default = "rg-fiapgames-prod"
}

variable "aks_name" {
  type    = string
  default = "aks-fiapgames-prod"
}

variable "node_vm_size" {
  description = "One-node demo SKU; confirm regional quota and cost before apply."
  type        = string
  default     = "Standard_B2s"
}

variable "acr_resource_id" {
  description = "Resource ID of the existing private ACR."
  type        = string
}

variable "acr_login_server" {
  description = "Login server of the existing private ACR."
  type        = string
}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_user_assigned_identity" "workloads" {
  name                = "id-fiapgames-workloads-prod"
  resource_group_name = var.resource_group_name
}

locals {
  tags = {
    application = "fiap-cloud-games"
    component   = "aks-demo"
    environment = "production"
    managed_by  = "terraform"
  }
}

resource "azurerm_kubernetes_cluster" "fcg" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "aks-fiapgames-demo"
  sku_tier            = "Free"

  automatic_channel_upgrade = "patch"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name            = "system"
    node_count      = 1
    vm_size         = var.node_vm_size
    os_disk_size_gb = 64
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.fcg.kubelet_identity[0].object_id
}

resource "azurerm_federated_identity_credential" "auth_api" {
  name                = "aks-auth-api"
  resource_group_name = var.resource_group_name
  parent_id           = data.azurerm_user_assigned_identity.workloads.id
  issuer              = azurerm_kubernetes_cluster.fcg.oidc_issuer_url
  subject             = "system:serviceaccount:default:auth-api"
  audience            = ["api://AzureADTokenExchange"]
}

resource "azurerm_federated_identity_credential" "catalog_api" {
  name                = "aks-catalog-api"
  resource_group_name = var.resource_group_name
  parent_id           = data.azurerm_user_assigned_identity.workloads.id
  issuer              = azurerm_kubernetes_cluster.fcg.oidc_issuer_url
  subject             = "system:serviceaccount:default:catalog-api"
  audience            = ["api://AzureADTokenExchange"]
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.fcg.name
}

output "aks_oidc_issuer" {
  value = azurerm_kubernetes_cluster.fcg.oidc_issuer_url
}

output "acr_login_server" {
  value = var.acr_login_server
}
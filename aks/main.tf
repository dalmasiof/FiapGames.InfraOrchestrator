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
  description = "Smallest VM family currently allowed by the target subscription in Brazil South."
  type        = string
  default     = "Standard_D2_v4"
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

data "azurerm_key_vault" "main" {
  name                = "kv-fiapgames-64f434dd"
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

    upgrade_settings {
      max_surge = "10%"
    }
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

resource "azurerm_redis_cache" "catalog" {
  name                = "redis-fiapgames-64f434dd"
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"

  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_reserved = 2
    maxmemory_delta    = 2
    maxmemory_policy   = "allkeys-lru"
  }

  tags = local.tags
}

resource "azurerm_key_vault_secret" "redis_connection" {
  name         = "Redis--ConnectionString"
  key_vault_id = data.azurerm_key_vault.main.id
  value        = "${azurerm_redis_cache.catalog.hostname}:${azurerm_redis_cache.catalog.ssl_port},password=${azurerm_redis_cache.catalog.primary_access_key},ssl=True,abortConnect=False"
}

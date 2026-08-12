terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }

    azapi = {
      source  = "azure/azapi"
      version = "~> 1.12"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

variable "location" {
  description = "Azure region used by the FIAP Cloud Games production resources."
  type        = string
  default     = "brazilsouth"
}

variable "sql_admin_login" {
  description = "Administrator login used only to provision the Azure SQL logical server."
  type        = string
  default     = "fiapgamesadmin"
}

variable "sql_admin_password" {
  description = "Administrator password used only to provision the Azure SQL logical server."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_admin_password) >= 16
    error_message = "The SQL administrator password must contain at least 16 characters."
  }
}

variable "rabbitmq_default_user" {
  description = "RabbitMQ administrator username stored as a Container App secret."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.rabbitmq_default_user)) >= 3
    error_message = "The RabbitMQ administrator username must contain at least 3 characters."
  }
}

variable "rabbitmq_default_password" {
  description = "RabbitMQ administrator password stored as a Container App secret."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.rabbitmq_default_password) >= 16
    error_message = "The RabbitMQ administrator password must contain at least 16 characters."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name displayed by Azure API Management."
  type        = string
  default     = "FIAP Cloud Games"
}

variable "apim_publisher_email" {
  description = "Publisher contact used by Azure API Management."
  type        = string
  default     = "cloud@fiapgames.com.br"
}

variable "configure_apim_apis" {
  description = "Configures APIM APIs and ingress restrictions after the API Container Apps have been deployed."
  type        = bool
  default     = false
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily Log Analytics ingestion cap for the economical environment."
  type        = number
  default     = 0.1

  validation {
    condition     = var.log_analytics_daily_quota_gb >= 0.1
    error_message = "The Log Analytics daily quota must be at least 0.1 GB."
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_container_app" "auth" {
  count = var.configure_apim_apis ? 1 : 0

  name                = "ca-auth-api"
  resource_group_name = local.resource_group_name

  depends_on = [azurerm_resource_group.main]
}

data "azurerm_container_app" "catalog" {
  count = var.configure_apim_apis ? 1 : 0

  name                = "ca-catalog-api"
  resource_group_name = local.resource_group_name

  depends_on = [azurerm_resource_group.main]
}

data "azurerm_container_app" "payment" {
  count = var.configure_apim_apis ? 1 : 0

  name                = "ca-payment-api"
  resource_group_name = local.resource_group_name

  depends_on = [azurerm_resource_group.main]
}

locals {
  resource_group_name = "rg-fiapgames-prod"
  unique_suffix       = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)

  database_names = toset([
    "fiapgames_auth",
    "fiapgames_catalog",
    "fiapgames_payment",
    "fiapgames_notification"
  ])

  common_tags = {
    application = "fiap-cloud-games"
    environment = "production"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_container_registry" "main" {
  name                = "acrfiapgamesprod${local.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.common_tags
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-fiapgames-${local.unique_suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true
  tags                       = local.common_tags
}

resource "azurerm_role_assignment" "current_user_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_user_assigned_identity" "workloads" {
  name                = "id-fiapgames-workloads-prod"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "workloads_key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workloads.principal_id
}

locals {
  application_secrets = {
    "ConnectionStrings--AuthConnection"         = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=fiapgames_auth;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "ConnectionStrings--CatalogConnection"      = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=fiapgames_catalog;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "ConnectionStrings--NotificationConnection" = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=fiapgames_notification;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "ConnectionStrings--PaymentConnection"      = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=fiapgames_payment;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "RabbitMq--HostName"                        = azurerm_container_app.rabbitmq.ingress[0].fqdn
    "RabbitMq--Port"                            = "5672"
    "RabbitMq--UserName"                        = var.rabbitmq_default_user
    "RabbitMq--Password"                        = var.rabbitmq_default_password
  }
}

moved {
  from = azurerm_key_vault_secret.database_connection_strings
  to   = azurerm_key_vault_secret.application
}

resource "azurerm_key_vault_secret" "application" {
  for_each = local.application_secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.current_user_key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "jwt_jwks_uri" {
  count = var.configure_apim_apis ? 1 : 0

  name         = "Jwt--JwksUri"
  value        = "https://${data.azurerm_container_app.auth[0].ingress[0].fqdn}/.well-known/jwks"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.current_user_key_vault_secrets_officer]
}

resource "azurerm_mssql_server" "main" {
  name                         = "sql-fiapgames-prod-${local.unique_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  tags                         = local.common_tags

  lifecycle {
    ignore_changes = [administrator_login_password]
  }
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "services" {
  for_each = local.database_names

  name           = each.value
  server_id      = azurerm_mssql_server.main.id
  sku_name       = "Basic"
  max_size_gb    = 2
  zone_redundant = false
  tags           = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-fiapgames-prod-${local.unique_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_analytics_daily_quota_gb
  tags                = local.common_tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-fiapgames-prod"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.common_tags

}

resource "azurerm_api_management" "main" {
  name                = "apim-fiapgames-prod"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_api_management_api" "auth" {
  count = var.configure_apim_apis ? 1 : 0

  name                  = "fiapgames-auth"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "FIAP Games Users API"
  path                  = "users"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${data.azurerm_container_app.auth[0].ingress[0].fqdn}"

  import {
    content_format = "openapi-link"
    content_value  = "https://${data.azurerm_container_app.auth[0].ingress[0].fqdn}/swagger/v1/swagger.json"
  }
}

resource "azurerm_api_management_api" "catalog" {
  count = var.configure_apim_apis ? 1 : 0

  name                  = "fiapgames-catalog"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "FIAP Games Catalog API"
  path                  = "catalog"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${data.azurerm_container_app.catalog[0].ingress[0].fqdn}"

  import {
    content_format = "openapi-link"
    content_value  = "https://${data.azurerm_container_app.catalog[0].ingress[0].fqdn}/swagger/v1/swagger.json"
  }
}

resource "azurerm_api_management_api" "payment" {
  count = var.configure_apim_apis ? 1 : 0

  name                  = "fiapgames-payment"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "FIAP Games Payment API"
  path                  = "payment"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${data.azurerm_container_app.payment[0].ingress[0].fqdn}"

  import {
    content_format = "openapi-link"
    content_value  = "https://${data.azurerm_container_app.payment[0].ingress[0].fqdn}/swagger/v1/swagger.json"
  }
}

resource "azurerm_api_management_policy" "global" {
  api_management_id = azurerm_api_management.main.id
  xml_content       = file("${path.module}/policies/global-cors.xml")
}

resource "azurerm_api_management_api_policy" "users" {
  count = var.configure_apim_apis ? 1 : 0

  api_name            = azurerm_api_management_api.auth[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = templatefile("${path.module}/policies/users-jwt.xml", {
    auth_internal_fqdn = data.azurerm_container_app.auth[0].ingress[0].fqdn
  })
}

resource "azurerm_api_management_api_policy" "catalog" {
  count = var.configure_apim_apis ? 1 : 0

  api_name            = azurerm_api_management_api.catalog[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = templatefile("${path.module}/policies/catalog-jwt.xml", {
    auth_internal_fqdn = data.azurerm_container_app.auth[0].ingress[0].fqdn
  })
}

resource "azurerm_api_management_api_policy" "payment" {
  count = var.configure_apim_apis ? 1 : 0

  api_name            = azurerm_api_management_api.payment[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = templatefile("${path.module}/policies/payment-jwt.xml", {
    auth_internal_fqdn = data.azurerm_container_app.auth[0].ingress[0].fqdn
  })
}

resource "terraform_data" "api_ingress_apim_only" {
  for_each = var.configure_apim_apis ? {
    auth = {
      id   = data.azurerm_container_app.auth[0].id
      name = data.azurerm_container_app.auth[0].name
    }
    catalog = {
      id   = data.azurerm_container_app.catalog[0].id
      name = data.azurerm_container_app.catalog[0].name
    }
    payment = {
      id   = data.azurerm_container_app.payment[0].id
      name = data.azurerm_container_app.payment[0].name
    }
  } : {}

  triggers_replace = [
    each.value.id,
    azurerm_api_management.main.public_ip_addresses[0]
  ]

  provisioner "local-exec" {
    command = <<-EOT
      az containerapp ingress access-restriction set --name ${each.value.name} --resource-group ${azurerm_resource_group.main.name} --rule-name Allow-APIM --ip-address ${azurerm_api_management.main.public_ip_addresses[0]}/32 --action Allow --description APIM-only --output none
    EOT
  }

  depends_on = [
    azurerm_api_management_api.auth,
    azurerm_api_management_api.catalog,
    azurerm_api_management_api.payment,
    azurerm_api_management_api_policy.users,
    azurerm_api_management_api_policy.catalog,
    azurerm_api_management_api_policy.payment
  ]
}

resource "azurerm_container_app" "rabbitmq" {
  name                         = "ca-rabbitmq-prod"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  secret {
    name  = "rabbitmq-default-user"
    value = var.rabbitmq_default_user
  }

  secret {
    name  = "rabbitmq-default-password"
    value = var.rabbitmq_default_password
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "rabbitmq"
      image  = "rabbitmq:3-management"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "RABBITMQ_DEFAULT_USER"
        secret_name = "rabbitmq-default-user"
      }

      env {
        name        = "RABBITMQ_DEFAULT_PASS"
        secret_name = "rabbitmq-default-password"
      }

      startup_probe {
        transport               = "TCP"
        port                    = 5672
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 10
      }

      liveness_probe {
        transport               = "TCP"
        port                    = 5672
        interval_seconds        = 10
        timeout                 = 3
        failure_count_threshold = 3
      }
    }
  }

  ingress {
    external_enabled = false
    target_port      = 5672
    exposed_port     = 5672
    transport        = "tcp"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# AzureRM 3.x models only the primary ingress port. Use the Azure API to add
# RabbitMQ's management port to the same internal-only Container App ingress.
resource "azapi_update_resource" "rabbitmq_management_port" {
  type        = "Microsoft.App/containerApps@2025-07-01"
  resource_id = azurerm_container_app.rabbitmq.id

  body = jsonencode({
    properties = {
      configuration = {
        secrets = [
          {
            name  = "rabbitmq-default-user"
            value = var.rabbitmq_default_user
          },
          {
            name  = "rabbitmq-default-password"
            value = var.rabbitmq_default_password
          }
        ]
        ingress = {
          additionalPortMappings = [
            {
              external    = false
              targetPort  = 15672
              exposedPort = 15672
            }
          ]
        }
      }
    }
  })
}

output "workload_managed_identity_resource_id" {
  description = "Value for the AZURE_MANAGED_IDENTITY_RESOURCE_ID GitHub variable."
  value       = azurerm_user_assigned_identity.workloads.id
}

output "workload_managed_identity_client_id" {
  description = "Value for the AZURE_MANAGED_IDENTITY_CLIENT_ID GitHub variable."
  value       = azurerm_user_assigned_identity.workloads.client_id
}

output "api_gateway_url" {
  description = "Public base URL for the only supported external entry point."
  value       = azurerm_api_management.main.gateway_url
}

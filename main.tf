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

variable "grafana_admin_password" {
  description = "Administrator password for the self-hosted Grafana Container App. Defaults to the RabbitMQ password when omitted."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.grafana_admin_password == null || length(var.grafana_admin_password) >= 16
    error_message = "The Grafana administrator password must contain at least 16 characters when provided."
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

data "azurerm_container_app" "rabbitmq" {
  name                = "ca-rabbitmq-prod"
  resource_group_name = local.resource_group_name

  depends_on = [azurerm_resource_group.main]
}

locals {
  resource_group_name = "rg-fiapgames-prod"
  unique_suffix       = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)
  redis_name          = "redis-fiapgames-prod"
  cosmos_name         = "cosmos-fiapgames-prod"

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

  grafana_password        = coalesce(var.grafana_admin_password, var.rabbitmq_default_password)
  api_gateway_host        = replace(replace(azurerm_api_management.main.gateway_url, "https://", ""), "http://", "")
  prometheus_internal_url = "http://ca-prometheus-prod:9090"
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
    "RabbitMq--HostName"                        = data.azurerm_container_app.rabbitmq.ingress[0].fqdn
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

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_key_vault_secret" "jwt_jwks_uri" {
  count = var.configure_apim_apis ? 1 : 0

  name         = "Jwt--JwksUri"
  value        = "${azurerm_api_management.main.gateway_url}/users/.well-known/jwks"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.current_user_key_vault_secrets_officer]

  lifecycle {
    ignore_changes = [value]
  }
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

resource "azurerm_redis_cache" "catalog_cache" {
  name                          = local.redis_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  capacity                      = 0
  family                        = "C"
  sku_name                      = "Basic"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.common_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_cosmosdb_account" "notification_history" {
  name                = local.cosmos_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "MongoDB"
  tags                = local.common_tags

  automatic_failover_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = false
  }

  lifecycle {
    ignore_changes = [capabilities]
  }
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

  lifecycle {
    ignore_changes = all
  }
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

resource "azurerm_api_management_api_operation" "auth_metrics" {
  count = var.configure_apim_apis ? 1 : 0

  operation_id        = "auth-metrics"
  api_name            = azurerm_api_management_api.auth[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Auth metrics"
  method              = "GET"
  url_template        = "/metrics"
}

resource "azurerm_api_management_api_operation" "catalog_metrics" {
  count = var.configure_apim_apis ? 1 : 0

  operation_id        = "catalog-metrics"
  api_name            = azurerm_api_management_api.catalog[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Catalog metrics"
  method              = "GET"
  url_template        = "/metrics"
}

resource "azurerm_api_management_api_operation" "payment_metrics" {
  count = var.configure_apim_apis ? 1 : 0

  operation_id        = "payment-metrics"
  api_name            = azurerm_api_management_api.payment[0].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Payment metrics"
  method              = "GET"
  url_template        = "/metrics"
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

resource "azurerm_container_app" "prometheus" {
  name                         = "ca-prometheus-prod"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "prometheus"
      image  = "prom/prometheus:v2.55.1"
      cpu    = 0.25
      memory = "0.5Gi"

      command = ["/bin/sh", "-c"]
      args    = ["printf '%s\\n' 'global:' '  scrape_interval: 15s' 'scrape_configs:' '  - job_name: fiapgames-auth' '    scheme: https' '    metrics_path: /users/metrics' '    static_configs:' '      - targets: [''${local.api_gateway_host}'']' '  - job_name: fiapgames-catalog' '    scheme: https' '    metrics_path: /catalog/metrics' '    static_configs:' '      - targets: [''${local.api_gateway_host}'']' '  - job_name: fiapgames-payment' '    scheme: https' '    metrics_path: /payment/metrics' '    static_configs:' '      - targets: [''${local.api_gateway_host}'']' > /tmp/prometheus.yml; exec /bin/prometheus --config.file=/tmp/prometheus.yml --storage.tsdb.path=/tmp/prometheus"]
    }
  }

  ingress {
    external_enabled = false
    target_port      = 9090
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "azurerm_container_app" "grafana" {
  name                         = "ca-grafana-prod"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  secret {
    name  = "grafana-admin-password"
    value = local.grafana_password
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "grafana"
      image  = "grafana/grafana:11.3.0"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "GF_SECURITY_ADMIN_USER"
        value = "admin"
      }

      env {
        name        = "GF_SECURITY_ADMIN_PASSWORD"
        secret_name = "grafana-admin-password"
      }

      env {
        name  = "GF_AUTH_ANONYMOUS_ENABLED"
        value = "false"
      }

      env {
        name  = "GF_DATASOURCES_DEFAULT_NAME"
        value = "Prometheus"
      }

      env {
        name  = "GF_DATASOURCES_DEFAULT_TYPE"
        value = "prometheus"
      }

      env {
        name  = "GF_DATASOURCES_DEFAULT_URL"
        value = local.prometheus_internal_url
      }

      env {
        name  = "GF_PATHS_PROVISIONING"
        value = "/tmp/grafana-provisioning"
      }

      command = ["/bin/sh", "-c"]
      args    = ["mkdir -p /tmp/grafana-provisioning/datasources /tmp/grafana-provisioning/dashboards; printf '%s\\n' 'apiVersion: 1' 'datasources:' '  - name: Prometheus' '    uid: prometheus' '    type: prometheus' '    access: proxy' '    url: http://ca-prometheus-prod:9090' '    isDefault: true' > /tmp/grafana-provisioning/datasources/prometheus.yaml; printf '%s\\n' 'apiVersion: 1' 'providers:' '  - name: FIAP Games' '    orgId: 1' '    type: file' '    disableDeletion: true' '    updateIntervalSeconds: 30' '    options:' '      path: /tmp/grafana-provisioning/dashboards' > /tmp/grafana-provisioning/dashboards/provider.yaml; echo '${filebase64("${path.module}/grafana/dashboards/fiapgames-overview.json")}' | base64 -d > /tmp/grafana-provisioning/dashboards/fiapgames-overview.json; exec /run.sh"]

    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http"

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
  resource_id = data.azurerm_container_app.rabbitmq.id

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

output "redis_hostname" {
  description = "Hostname of the Redis cache used by the Catalog API."
  value       = azurerm_redis_cache.catalog_cache.hostname
}

output "redis_primary_key" {
  description = "Primary access key for Redis. Use it only in managed secret stores."
  value       = azurerm_redis_cache.catalog_cache.primary_access_key
  sensitive   = true
}

output "cosmos_account_name" {
  description = "Name of the Cosmos DB account used by Notification for Mongo API."
  value       = azurerm_cosmosdb_account.notification_history.name
}

output "cosmos_endpoint" {
  description = "Cosmos DB endpoint for MongoDB connection strings."
  value       = azurerm_cosmosdb_account.notification_history.endpoint
  sensitive   = true
}

output "grafana_url" {
  description = "Public URL for the self-hosted Grafana dashboard."
  value       = "https://${azurerm_container_app.grafana.ingress[0].fqdn}"
}

output "prometheus_internal_url" {
  description = "Internal URL used by Grafana to query Prometheus."
  value       = local.prometheus_internal_url
}

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "256df3c7-8788-448d-9633-aa72f5256bb3"
    tenant_id= "dd64b6ec-0a2a-4f60-8ca1-eeaab33884d7"
}

data "azurerm_key_vault" "dbvault" {
  name                = var.vault
  resource_group_name = var.resource_group_name
}

data "azurerm_key_vault_secret" "dbadminuser" {
  name         = "missadministrator"
  key_vault_id = data.azurerm_key_vault.dbvault.id
}

output "secret_value" {
  value = data.azurerm_key_vault_secret.dbadminuser.value
  sensitive   = true
}

resource "azurerm_sql_firewall_rule" "fw" {
  name                = "DB-fwrules"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_sql_server.primary.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

resource "azurerm_storage_account" "example" {
  name                     = "examplemydbstacct"
  resource_group_name      = var.resource_group_name
  location                 = var.primary_location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
}

resource "azurerm_sql_server" "primary" {
  name                         = "${var.sqlserver-name}-primary"
  resource_group_name          = var.resource_group_name
  location                     = var.primary_location
  version                      = "12.0"
  administrator_login          = data.azurerm_key_vault_secret.dbadminuser.name
  administrator_login_password = data.azurerm_key_vault_secret.dbadminuser.value
  #minimum_tls_version          = "1.2"
    
  tags = {
    foo = "bar"
  }
}

resource "azurerm_sql_server" "secondary" {
  name                         = "${var.sqlserver-name}-secondary"
  resource_group_name          = var.resource_group_name
  location                     = var.secondary_location
  version                      = "12.0"
  administrator_login          = data.azurerm_key_vault_secret.dbadminuser.name
  administrator_login_password = data.azurerm_key_vault_secret.dbadminuser.value
  #minimum_tls_version          = "1.2"
    
  tags = {
    foo = "bar"
  }
}

resource "azurerm_mssql_database" "db" {
  name           = "DemoDB"
  server_id      = azurerm_sql_server.primary.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 2
  read_scale     = true
  sku_name       = "BC_Gen5_2"
  zone_redundant = true

  tags = {
    foo = "bar"
  }

}

resource "azurerm_mssql_server_extended_auditing_policy" "example" {
  server_id                               = azurerm_sql_server.primary.id
  storage_endpoint                        = azurerm_storage_account.example.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.example.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
}

resource "azurerm_mssql_database_extended_auditing_policy" "example" {
  database_id                             = azurerm_mssql_database.db.id
  storage_endpoint                        = azurerm_storage_account.example.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.example.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
}

resource "azurerm_sql_failover_group" "example" {
  name                = "db-failover-group"
  resource_group_name = azurerm_sql_server.primary.resource_group_name
  server_name         = azurerm_sql_server.primary.name
  databases           = [azurerm_mssql_database.db.id]
  partner_servers {
    id = azurerm_sql_server.secondary.id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }
}

# Providers Block
provider "azurerm" {
  features {}
}

# Creates My Main resource group
resource "azurerm_resource_group" "rg" {
  name     = "uo-rg"
  location = "East US"
}

# Creates a virtual network called DevVnet for my Resources
resource "azurerm_virtual_network" "avn" {
  name                = "DevVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Creates a subnet called Web
resource "azurerm_subnet" "web" {
  name                 = "Web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.0.1.0/24"]
}


# Creates a subnet called app
resource "azurerm_subnet" "app" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.0.2.0/24"]
}


# Creates a subnet called Database
resource "azurerm_subnet" "database" {
  name                 = "Database"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.0.3.0/24"]
}


# Creates an internal Load Balancer called AppLB for my architecture
resource "azurerm_lb" "app_lb" {
  name                = "AppLB"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "InternalAppLB"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.5"
  }
}


# Creates a backend pool for web subnet
resource "azurerm_lb_backend_address_pool" "web_subnet_backend_pool" {
  loadbalancer_id     = azurerm_lb.app_lb.id
  name                = "WebSubnetBackendPool"
}

# Creates a backend pool for my app subnet
resource "azurerm_lb_backend_address_pool" "app_subnet_backend_pool" {
  loadbalancer_id     = azurerm_lb.app_lb.id
  name                = "AppSubnetBackendPool"
}

# Creates a Probe for my web subnet
resource "azurerm_lb_probe" "web_subnet_probe" {
  loadbalancer_id     = azurerm_lb.app_lb.id
  name                = "WebSubnetProbe"
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 15
  number_of_probes    = 3
}


# Creates a probe for app subnet
resource "azurerm_lb_probe" "app_subnet_probe" {
  loadbalancer_id     = azurerm_lb.app_lb.id
  name                = "AppSubnetProbe"
  protocol            = "Tcp"
  port                = 8080
  interval_in_seconds = 15
  number_of_probes    = 3
}

# Creates LB rule for web subnet
resource "azurerm_lb_rule" "web_subnet_lb_rule" {
  loadbalancer_id                = azurerm_lb.app_lb.id
  name                           = "WebSubnetLBRule"
  frontend_ip_configuration_name = azurerm_lb.app_lb.frontend_ip_configuration[0].name
  probe_id                       = azurerm_lb_probe.web_subnet_probe.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
}

# Creates a LB rule for app Subnet
resource "azurerm_lb_rule" "app_subnet_lb_rule" {
  loadbalancer_id                = azurerm_lb.app_lb.id
  name                           = "AppSubnetLBRule"
  frontend_ip_configuration_name = azurerm_lb.app_lb.frontend_ip_configuration[0].name
  probe_id                       = azurerm_lb_probe.app_subnet_probe.id
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
}



# Creates a primary mssql server
resource "azurerm_mssql_server" "primary_server" {
  name                         = "devdb-sqlserver"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "MyStrongPassword!"
}

# Creates a database called DevDB for the Primary mssql server
resource "azurerm_mssql_database" "Dev_DB" {
  name           = "DevDB"
  server_id      = azurerm_mssql_server.primary_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 5
#  read_scale     = true
  sku_name       = "S0"
#  zone_redundant = true
}


# for allowing traffic between our Azure SQL server and our database subnet of our virtual network.
resource "azurerm_mssql_virtual_network_rule" "vnr" {
  name      = "sql-vnet-rule"
  ignore_missing_vnet_service_endpoint = true
  server_id = azurerm_mssql_server.primary_server.id
  subnet_id = azurerm_subnet.database.id
}


# Creates a sql firewall rule for the app subnet
resource "azurerm_mssql_firewall_rule" "app_subnet_firewall_rule" {
  name                = "allow-app-subnet"
  server_id         = azurerm_mssql_server.primary_server.id
  start_ip_address    = "10.0.2.0"   # Start IP of the App subnet
  end_ip_address      = "10.0.2.255" # End IP of the App subnet
}



# Creates New resource group for the secondary mssql server
resource "azurerm_resource_group" "rg-2" {
  name     = "database-rg"
  location = "West US"
}


# Create Secondary mssql server
resource "azurerm_mssql_server" "secondary_server" {
  name                         = "secondary-sqlserver"
  resource_group_name          = azurerm_resource_group.rg-2.name
  location                     = "West US"
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "MyStrongPassword!"
}


# Creates a mssql failover group
resource "azurerm_mssql_failover_group" "fg" {
  name      = "uo-fo"
  server_id = azurerm_mssql_server.primary_server.id
  databases = [
    azurerm_mssql_database.Dev_DB.id
  ]

  partner_server {
    id = azurerm_mssql_server.secondary_server.id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }

  tags = {
    environment = "prod"
    database    = "DevDB"
  }
}



# Creates a log analytics workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = "my-log-analytics-workspace"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}



# Enable log and metric collection
resource "azurerm_monitor_diagnostic_setting" "mds" {
  name               = "my-monitor-diagnostic-setting"
    target_resource_id = azurerm_mssql_database.Dev_DB.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}


# Create an azure action group for our operations team
resource "azurerm_monitor_action_group" "ag" {
  name                = "operations-action-group"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "ops-action"

  email_receiver {
    name          = "SendToOperations"
    email_address = "operations@operations.com"
  }
}


# Creates Metric alerts for the Ops Team
resource "azurerm_monitor_metric_alert" "dtu_alert" {
  name                = "database-dtu-alert"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_mssql_database.Dev_DB.id]
  description         = "Alert on high DTU percentage"
  severity            = 3

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 70
  }

  action {
    action_group_id = azurerm_monitor_action_group.ag.id
  }
}


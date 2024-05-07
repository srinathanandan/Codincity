# terraform block (azure provider)
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.101.0"
    }
  }

  # keep the state files in remote location
  backend "azurerm" {
    resource_group_name  = "codincitysa-rg"
    storage_account_name = "codincitysa"
    container_name       = "tfstatecont"
    key                  = "terraform.tfstate"
  }
}

# provider block (credentials for azure)
provider "azurerm" {
   features {}
   subscription_id = ""
   tenant_id = ""
   client_id = ""
   client_secret = ""
}

# create a resource group
resource "azurerm_resource_group" "arg" {
  name     = "codincity-rg"
  location = "East US"
}

# create an azure load balancer

resource "azurerm_virtual_network" "avn" {
  name                = "codincity-network"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  address_space       = ["10.254.0.0/16"]
}

resource "azurerm_subnet" "asn" {
  name                 = "codincity-snet"
  resource_group_name  = azurerm_resource_group.arg.name
  virtual_network_name = azurerm_virtual_network.avn.name
  address_prefixes     = ["10.254.0.0/24"]
}

resource "azurerm_public_ip" "apip" {
  name                = "codincity-pip"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  allocation_method   = "Static"
  sku = "Standard"
}

# since these variables are re-used - a locals block makes this more maintainable
locals {
  backend_address_pool_name      = "${azurerm_virtual_network.avn.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.avn.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.avn.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.avn.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.avn.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.avn.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.avn.name}-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
  name                = "codincity-appgateway"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.asn.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.apip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}


# create a kubernetes service

resource "azurerm_kubernetes_cluster" "akc" {
  name                = "codincityaks"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name
  dns_prefix          = "caks1"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

# create a azure container registry
resource "azurerm_container_registry" "acr" {
  name                = "codincityregistry"
  resource_group_name = azurerm_resource_group.arg.name
  location            = azurerm_resource_group.arg.location
  sku                 = "Standard"
}

# create a azure postgresql
resource "azurerm_postgresql_server" "apss" {
  name                = "codincitypostgresql-server-1"
  location            = azurerm_resource_group.arg.location
  resource_group_name = azurerm_resource_group.arg.name

  sku_name = "B_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true
  version                      = "9.5"
  ssl_enforcement_enabled      = true
}

resource "azurerm_postgresql_database" "example" {
  name                = "apdb"
  resource_group_name = azurerm_resource_group.arg.name
  server_name         = azurerm_postgresql_server.apss.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

resource "azurerm_role_assignment" "aks_to_acr_role" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.akc.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# terraform init
# terraform validate
# terraform plan
# terraform apply
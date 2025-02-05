provider "azurerm" {
  features {}
}

locals {
  name        = "testing"
  environment = "app"
  label_order = ["name", "environment"]
}

##-----------------------------------------------------------------------------
## Resource Group module call
## Resource group in which all resources will be deployed.
##-----------------------------------------------------------------------------
module "resource_group" {
  source      = "git::https://github.com/yadavprakash/terraform-azure-resource-group.git?ref=v1.0.0"
  name        = local.name
  environment = local.environment
  label_order = local.label_order
  location    = "Canada Central"
}

##-----------------------------------------------------------------------------
## Virtual Network module call.
##-----------------------------------------------------------------------------
module "vnet" {
  depends_on          = [module.resource_group]
  source              = "git::https://github.com/yadavprakash/terraform-azure-vnet.git?ref=v1.0.0"
  name                = local.name
  environment         = local.environment
  resource_group_name = module.resource_group.resource_group_name
  location            = module.resource_group.resource_group_location
  address_spaces      = ["10.30.0.0/22"]
}

##-----------------------------------------------------------------------------
## Subnet Module call.
## Subnet to which network security group will be attached.
##-----------------------------------------------------------------------------
module "subnet" {
  source               = "git::https://github.com/yadavprakash/terraform-azure-subnet.git?ref=v1.0.1"
  name                 = local.name
  environment          = local.environment
  resource_group_name  = module.resource_group.resource_group_name
  location             = module.resource_group.resource_group_location
  virtual_network_name = join("", [module.vnet.vnet_name])
  # Subnet Configuration
  subnet_names    = ["subnet"]
  subnet_prefixes = ["10.30.0.0/24"]
  # routes
  enable_route_table = true
  route_table_name   = "default_subnet"
  # routes
  routes = [
    {
      name           = "rt-test"
      address_prefix = "0.0.0.0/0"
      next_hop_type  = "Internet"
    }
  ]
}

##-----------------------------------------------------------------------------
## Log Analytics module call.
## Log Analytics workspace in which network security group diagnostic setting logs will be received.
##-----------------------------------------------------------------------------
module "log-analytics" {
  source                           = "git::https://github.com/yadavprakash/terraform-azure-log-analytics.git?ref=v1.0.0"
  name                             = local.name
  environment                      = local.environment
  label_order                      = local.label_order
  create_log_analytics_workspace   = true
  resource_group_name              = module.resource_group.resource_group_name
  log_analytics_workspace_location = module.resource_group.resource_group_location

  #### diagnostic setting
  log_analytics_workspace_id = module.log-analytics.workspace_id
}

##-----------------------------------------------------------------------------
## Network Security Group module call.
##-----------------------------------------------------------------------------
module "network_security_group" {
  depends_on              = [module.subnet]
  source                  = "../."
  name                    = local.name
  environment             = local.environment
  resource_group_name     = module.resource_group.resource_group_name
  resource_group_location = module.resource_group.resource_group_location
  subnet_ids              = module.subnet.subnet_id
  inbound_rules = [
    {
      name                  = "ssh"
      priority              = 101
      access                = "Allow"
      protocol              = "Tcp"
      source_address_prefix = "10.20.0.0/32"
      #source_address_prefixes    = ["10.20.0.0/32","10.21.0.0/32"]
      source_port_range          = "*"
      destination_address_prefix = "0.0.0.0/0"
      destination_port_range     = "22"
      description                = "ssh allowed port"
    },
    {
      name                       = "https"
      priority                   = 102
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "80,443"
      destination_address_prefix = "0.0.0.0/0"
      destination_port_range     = "22"
      description                = "ssh allowed port"
    }
  ]
  enable_diagnostic          = true
  log_analytics_workspace_id = module.log-analytics.workspace_id
}

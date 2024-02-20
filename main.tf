## Main config
# How to use this provider
# To install this provider, copy and paste this code into your Terraform configuration. Then, run terraform init.

terraform {
  #required_version = ">= 0.13"
  required_providers {
    vcd = {
      source = "vmware/vcd"
      version = "3.10.0"
    }
  }
  backend "s3" {
    bucket = "terraform"
    key = "timo/terraform.tfstate"
    region = "us-east-1"
    endpoint = "s3-north1.viettelidc.com.vn"
    force_path_style            = true
    skip_metadata_api_check     = true
    skip_credentials_validation = true
  }
}


# data "terraform_remote_state" "network" {
#   backend = "s3"
#   config = {
#     bucket = "terraform"
#     key    = "timo/terraform.tfstate"
#     region = "us-east-1"
#   }
# }

## Providers definition
provider "vcd" {
  user                 = var.vcd_user
  password             = var.vcd_pass
  org                  = var.org_name
  vdc                  = var.vdc_name
  auth_type            = "integrated"
  url                  = var.vcd_url
  max_retry_timeout    = var.vcd_max_retry_timeout
  allow_unverified_ssl = var.vcd_allow_unverified_ssl
  logging              = true
  logging_file         = "tenant-debug.log"
}

# Data for vcd org
data "vcd_org" "org" {
  name = var.org_name
}

# Data for vcd catalog, image template
data "vcd_catalog" "atm" {
  org  = "VTDC" #catalog form Viettel IDC
  name = "VM TEMPLATES"
}

# List image templates
data "vcd_catalog_vapp_template" "atm-ubuntu2004" {
  org        = var.org_name
  catalog_id = data.vcd_catalog.atm.id
  name       = "ATMA-Ubuntu20.04"
}
data "vcd_catalog_vapp_template" "atm-ubuntu2204" {
  org        = var.org_name
  catalog_id = data.vcd_catalog.atm.id
  name       = "ATMA-Ubuntu22.04"
}
data "vcd_catalog_vapp_template" "atm-win2k12r2" {
  org        = var.org_name
  catalog_id = data.vcd_catalog.atm.id
  name       = "ATMA-Win2k12R2-Std"
}
data "vcd_catalog_vapp_template" "atm-win2k16" {
  org        = var.org_name
  catalog_id = data.vcd_catalog.atm.id
  name       = "ATMA-Win2k16-Std"
}

data "vcd_org_vdc" "vdc-dev" {
  name = "8001350-Dev"
}

data "vcd_org_vdc" "vdc-prod" {
  name = "8001350-Prod"
}

data "vcd_org_vdc" "vdc-sharing" {
  name = "8001350-Sharing"
}

data "vcd_org_vdc" "vdc-staging" {
  name = "8001350-Staging"
}

# Data for NSXT Edgegateway
data "vcd_nsxt_edgegateway" "nsxt-edge-dev" {
  org         = var.org_name
  name        = var.edge_gateway
  owner_id    = data.vcd_org_vdc.vdc-dev.id
}

data "vcd_vdc_group" "group" {
  name = "8001350-Datacenter Group-01"
}

# Data for NSXT Edgegateway
data "vcd_nsxt_edgegateway" "nsxt-edge-group" {
  org      = var.org_name
  owner_id = data.vcd_vdc_group.group.id
  name     = "8001350-Edge Gateway"
}

# Data for Network Internet Space
data "vcd_ip_space" "internet-space" {
  name        = var.internet_ip_space
}

#Start network NSX
#Private IP Space
// https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/ip_space
resource "vcd_ip_space" "local-space-dev" {
  name        = "terraform-local-dev"
  description = "Private IP Spaces are dedicated to a single tenant"
  type        = "PRIVATE"
  org_id      = data.vcd_org.org.id

  internal_scope = ["192.168.0.0/16", "10.0.0.0/16"] // max 5

  route_advertisement_enabled = false

  ip_prefix {
    default_quota = -1 # unlimited
    // Example: Allow allocated 20 prefix in scope 192
    prefix {
      first_ip      = "192.168.0.0"
      prefix_length = 24
      prefix_count  = 10
    }
    prefix {
      first_ip      = "192.168.100.0"
      prefix_length = 24
      prefix_count  = 10
    }
  }

  ip_prefix {
    default_quota = -1 # unlimited
    // Example: Allow allocated 8 prefix in scope 10
    prefix {
      first_ip      = "10.0.0.0"
      prefix_length = 30
      prefix_count  = 4
    }
    prefix {
      first_ip      = "10.0.1.0"
      prefix_length = 30
      prefix_count  = 4
    }
  }
}

#Provides a resource to manage IP Allocations within IP Spaces. 
#It supports both - Floating IPs (IPs from IP Ranges) and IP Prefix (subnet) allocations with manual and automatic reservations.
#Example IP Prefix
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/ip_space_ip_allocation#example-usage-floating-ip-usage-for-nat-rule
// Allocate 2 dải mạng trong scope bằng prefix
resource "vcd_ip_space_ip_allocation" "ip-prefix-192" {
  org_id        = data.vcd_org.org.id
  ip_space_id   = vcd_ip_space.local-space-dev.id
  type          = "IP_PREFIX"
  prefix_length = 24

  depends_on = [vcd_ip_space.local-space-dev]
}

// Chỉ định allocated cho dải 10.
// Trong TH cả 2 scope prefix đều /24 => allocate lần lượt từ nhỏ đến lớn, prefix nào tạo trước ưu tiên
// => Không chỉ định được dải
resource "vcd_ip_space_ip_allocation" "ip-prefix-10" {
  org_id        = data.vcd_org.org.id
  ip_space_id   = vcd_ip_space.local-space-dev.id
  type          = "IP_PREFIX"
  prefix_length = 30

  depends_on = [vcd_ip_space.local-space-dev]
}

#Provides a VMware Cloud Director Org VDC routed Network. This can be used to create, modify, and delete routed VDC networks (backed by NSX-T or NSX-V).
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/network_routed_v2
resource "vcd_network_routed_v2" "routed-network" {
  org             = var.org_name
  name            = "terraform-routed-network"
  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge-dev.id
  gateway         = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-192.ip_address, 253)
  prefix_length   = vcd_ip_space_ip_allocation.ip-prefix-192.prefix_length
  #prefix_length   = split("/", vcd_ip_space_ip_allocation.ip-prefix.ip_address)[1]

  static_ip_pool {
    start_address = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-192.ip_address, 2)
    end_address   = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-192.ip_address, 252)
  }
}

resource "vcd_network_isolated_v2" "isolated-network" {
  org      = var.org_name
  owner_id = data.vcd_org_vdc.vdc-dev.id

  name        = "terraform-nsxt-isolated"
  description = "My isolated Org VDC network backed by NSX-T. Use prefix 10."

  gateway         = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-10.ip_address, 2)
  prefix_length   = vcd_ip_space_ip_allocation.ip-prefix-10.prefix_length
  #prefix_length   = split("/", vcd_ip_space_ip_allocation.ip-prefix.ip_address)[1]

  static_ip_pool {
    start_address = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-10.ip_address, 1)
    end_address   = cidrhost(vcd_ip_space_ip_allocation.ip-prefix-10.ip_address, 1)
  }
}

#Stop network NSX

## Org vApp - vapp-web
resource "vcd_vapp" "vapp-web" {
   name = "Teraform-vapp-web"
   org = var.org_name
   vdc = var.vdc_name
}

# ## Use exited network
# data "vcd_network_routed" "routed-network" {
#   org              = var.org_name
#   vdc              = var.vdc_name
#   name             = "Tenant1-App Zone"
# }

## Org vApp Network
resource "vcd_vapp_org_network" "routed-network" {
  vapp_name        = vcd_vapp.vapp-web.name
  #org_network_name = data.vcd_network_routed.routed-network.name
  org_network_name = vcd_network_routed_v2.routed-network.name
  depends_on = [vcd_network_routed_v2.routed-network]
}

## VM 01 - web-backend
# Refer https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/vapp_vm
resource "vcd_vapp_vm" "web-backend" {
  //vdc       = var.vdc_name //data.vcd_org_vdc.vdc-dev.name Cần chỉ định VDC trong provider
  vapp_name = vcd_vapp.vapp-web.name
  name      = "web-backend"

  vapp_template_id = data.vcd_catalog_vapp_template.atm-ubuntu2204.id

  memory = 4096
  cpus   = 4

  network {
    type               = "org"
    name               = vcd_vapp_org_network.routed-network.org_network_name
    # Static pool
    ip_allocation_mode = "POOL"
    # Static IP address from a subnet defined in static pool for network
    #ip                 = "192.168.10.155"
    #ip_allocation_mode = "MANUAL"
  }

  override_template_disk {
    bus_type        = "paravirtual"
    size_in_mb      = "30720"
    bus_number      = 0
    unit_number     = 0
    iops            = 0
    storage_profile = "vSAN Gold Storage Service"
  }

  customization {
    force                      = false
    change_sid                 = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "Matkhaumoiroi1!"
  }

  depends_on = [vcd_vapp_org_network.routed-network]
}

## add disk
# https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/vm_internal_disk

resource "vcd_vm_internal_disk" "disk2" {
  vapp_name       = vcd_vapp.vapp-web.name
  vm_name         = vcd_vapp_vm.web-backend.name
  bus_type        = "sata"
  size_in_mb      = "13333"
  bus_number      = 0
  unit_number     = 1
  storage_profile = "vSAN Gold Storage Service"
  allow_vm_reboot = true
  depends_on      = [vcd_vapp_vm.web-backend]
}

#FW and NAT
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/nsxt_firewall
#Example rule to allow all IPv4 traffic from anywhere to anywhere)
resource "vcd_nsxt_firewall" "internet-192-168-100-0" {
  org           = var.org_name

  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge-dev.id

  rule {
    action           = "ALLOW"
    name             = "allow all IPv4 traffic"
    direction        = "IN_OUT" //One of IN, OUT, or IN_OUT
    ip_protocol      = "IPV4"
    #source_ids       = [vcd_nsxt_security_group.group.1.id] //A set of source object Firewall Groups (IP Sets or Security groups). Leaving it empty matches Any (all)
    #destination_ids  = vcd_nsxt_security_group.group.*.id
    #app_port_profile_ids = [data.vcd_nsxt_app_port_profile.ssh.id, vcd_nsxt_app_port_profile.custom-app.id] // (Optional) A set of Application Port Profiles. Leaving it empty matches Any (all)
  }
}

#Request an Internet Floating IP form Internet Space
resource "vcd_ip_space_ip_allocation" "internet-ip" {
  org_id        = data.vcd_org.org.id
  ip_space_id   = data.vcd_ip_space.internet-space.id
  type          = "FLOATING_IP"
}

#Supported in provider v3.3+ and VCD 10.1+ with NSX-T backed VDCs.
#Provides a resource to manage NSX-T NAT rules. To change the source IP address from a private to a public IP address, you create a source NAT (SNAT) rule. 
#To change the destination IP address from a public to a private IP address, you create a destination NAT (DNAT) rule.
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/nsxt_nat_rule
resource "vcd_nsxt_nat_rule" "snat-web" {
  org = var.org_name

  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge-dev.id

  name        = "SNAT WEB"
  rule_type   = "SNAT" //One of DNAT, NO_DNAT, SNAT, NO_SNAT, REFLEXIVE
  description = "test nat for web backend VM"

  # Using primary_ip from edge gateway
  external_address         = vcd_ip_space_ip_allocation.internet-ip.ip_address
  internal_address         = vcd_vapp_vm.web-backend.network[0].ip //IP of first NIC
  #snat_destination_address = "8.8.8.8"
  #logging                  = true

  depends_on = [vcd_vapp_vm.web-backend]
}
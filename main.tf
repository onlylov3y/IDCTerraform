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
}

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

# Data for NSXT Edgegateway
data "vcd_nsxt_edgegateway" "nsxt-edge" {
  org         = var.org_name
  name        = var.edge_gateway
}

# Data for Network Internet Space
data "vcd_ip_space" "internet-space" {
  name        = var.internet_ip_space
}

#Start network NSX
#Private IP Space
resource "vcd_ip_space" "local-space" {
  name        = "terraform-local-space"
  description = "Private IP Spaces are dedicated to a single tenant"
  type        = "PRIVATE"
  org_id      = data.vcd_org.org.id

  internal_scope = ["192.168.100.0/24", "192.168.200.0/24"]

  route_advertisement_enabled = false

  ip_prefix {
    default_quota = -1 # unlimited

    prefix {
      first_ip      = "192.168.100.0"
      prefix_length = 24
      prefix_count  = 1
    }
  }
}

#Provides a resource to manage IP Allocations within IP Spaces. 
#It supports both - Floating IPs (IPs from IP Ranges) and IP Prefix (subnet) allocations with manual and automatic reservations.
#Example IP Prefix
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/ip_space_ip_allocation#example-usage-floating-ip-usage-for-nat-rule

resource "vcd_ip_space_ip_allocation" "ip-prefix" {
  org_id        = data.vcd_org.org.id
  ip_space_id   = vcd_ip_space.local-space.id
  type          = "IP_PREFIX"
  prefix_length = 24

  depends_on = [vcd_ip_space.local-space]
}

#Provides a VMware Cloud Director Org VDC routed Network. This can be used to create, modify, and delete routed VDC networks (backed by NSX-T or NSX-V).
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/network_routed_v2
resource "vcd_network_routed_v2" "routed-network" {
  org             = var.org_name
  name            = "terraform-routed-network"
  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge.id
  gateway         = cidrhost(vcd_ip_space_ip_allocation.ip-prefix.ip_address, 1)
  prefix_length   = vcd_ip_space_ip_allocation.ip-prefix.prefix_length
  #prefix_length   = split("/", vcd_ip_space_ip_allocation.ip-prefix.ip_address)[1]

  static_ip_pool {
    start_address = cidrhost(vcd_ip_space_ip_allocation.ip-prefix.ip_address, 2)
    end_address   = cidrhost(vcd_ip_space_ip_allocation.ip-prefix.ip_address, 253)
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

  customization {
    force                      = false
    change_sid                 = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "passwd vm"
  }

  depends_on = [vcd_vapp_org_network.routed-network]
}

#FW and NAT
#https://registry.terraform.io/providers/vmware/vcd/latest/docs/resources/nsxt_firewall
#Example rule to allow all IPv4 traffic from anywhere to anywhere)
resource "vcd_nsxt_firewall" "internet-192-168-100-0" {
  org           = var.org_name

  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge.id

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

  edge_gateway_id = data.vcd_nsxt_edgegateway.nsxt-edge.id

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
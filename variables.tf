# vCloud Director Connection Variables
variable "vcd_user" {
    description = "vCloud user"
}

variable "vcd_pass" {
    description = "vCloud pass"
}

variable "vcd_url" {
    description = "vCloud url"
}

variable "vcd_max_retry_timeout" {
    description = "vCloud max retry timeout"
}

variable "vcd_allow_unverified_ssl" {
    description = "vCloud allow unverified ssl"
}

# vCloud Director Organization Variables
variable "org_name" {
    description = "Organization Name"
}
variable "vdc_name" {
    description = "VDC Name"
}
variable "edge_gateway" {
    description = "VDC Edge Gateway Name"
}
variable "internet_ip_space" {
    description = "VDC Internet Floating IP"
}
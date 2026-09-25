resource "nebius_vpc_v1_pool" "mlops_stand_ip_pool" {
  name     = "mlops_stand_ip_pool"
  parent_id = var.project_id
  version    = "IPV4"
  visibility = "PRIVATE"

  cidrs = [
    {
      cidr = "10.192.0.0/14"
    }
  ]
}

resource "nebius_vpc_v1_network" "mlops_stand_net" {
  name      = "mlops_stand_net"
  parent_id = var.project_id

  ipv4_private_pools = {
    pools = [
      {
        id = nebius_vpc_v1_pool.mlops_stand_ip_pool.id
      }
    ]
  }
}

resource "nebius_vpc_v1_subnet" "mlops_stand_subnet" {
  name       = "mlops_stand_subnet"
  parent_id  = var.project_id
  network_id = nebius_vpc_v1_network.mlops_stand_net.id

  ipv4_private_pools = {
    use_network_pools = true
  }
}

resource "nebius_vpc_v1_security_group" "default_secgroup" {
  name       = "default_secgroup"
  parent_id  = var.project_id
  network_id = nebius_vpc_v1_network.mlops_stand_net.id
}

resource "nebius_vpc_v1_security_rule" "allow_all_ingress" {
  name      = "allow-all-ingress"
  parent_id = nebius_vpc_v1_security_group.default_secgroup.id
  access    = "ALLOW"
  protocol  = "ANY"
  type      = "STATELESS"
  priority  = 500

  ingress = {
    source_cidrs      = []
    destination_ports = []
  }
}

resource "nebius_vpc_v1_security_rule" "allow_all_egress" {
  name      = "allow-all-egress"
  parent_id = nebius_vpc_v1_security_group.default_secgroup.id
  access    = "ALLOW"
  protocol  = "ANY"
  type      = "STATELESS"
  priority  = 500

  egress = {
    destination_cidrs = []
    destination_ports = []
  }
}
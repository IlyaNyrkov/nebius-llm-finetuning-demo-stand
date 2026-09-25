resource "nebius_mk8s_v1_cluster" "mlops_stand_k8s" {
  name      = "mlops-stand-k8s"
  parent_id = var.project_id

  control_plane = {
    subnet_id = nebius_vpc_v1_subnet.mlops_stand_subnet.id
    endpoints = {
      public_endpoint = {}
    }
  }
}

// CPU Only nodes

resource "nebius_mk8s_v1_node_group" "cpu-small" {
  name      = "cpu-small"
  parent_id = nebius_mk8s_v1_cluster.mlops_stand_k8s.id

  fixed_node_count = 2 // set to 1 if you only need mlflow

  template = {
    resources = {
      platform = "cpu-d3"
      preset   = "2vcpu-8gb"
    }

    os = "ubuntu24.04"

    boot_disk = {
      type           = "NETWORK_SSD"
      size_gibibytes = 100
    }

    network_interfaces = [
      {
        subnet_id = nebius_vpc_v1_subnet.mlops_stand_subnet.id
        security_groups = [
          {
            id = nebius_vpc_v1_security_group.default_secgroup.id
          }
        ]
      }
    ]

    cloud_init_user_data = <<-EOT
      #cloud-config
      users:
        - name: ilya
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
    EOT
  }
}

// GPU node
resource "nebius_mk8s_v1_node_group" "gpu_l40s" {
  name             = "gpu-only" 
  parent_id        = nebius_mk8s_v1_cluster.mlops_stand_k8s.id
  fixed_node_count = 1

  template = {
    resources = {
      platform = "gpu-l40s-a"       # Specify other model if L40s is not available
      preset   = "1gpu-8vcpu-32gb"  # smallest preset: 1 GPU, 8 vCPU, 32 GiB RAM
    }

    gpu_settings = {
      drivers_preset = "cuda13"     # preinstalled NVIDIA drivers
    }

    os = "ubuntu24.04"

    boot_disk = {
      type           = "NETWORK_SSD"
      size_gibibytes = 100
    }

    network_interfaces = [
      {
        subnet_id = nebius_vpc_v1_subnet.mlops_stand_subnet.id
        security_groups = [
          {
            id = nebius_vpc_v1_security_group.default_secgroup.id
          }
        ]
      }
    ]

    cloud_init_user_data = <<-EOT
      #cloud-config
      users:
        - name: ilya
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
    EOT

    # Preemptible (spot) node — cheaper, but can be stopped by Nebius at any time.
    preemptible = {}
    follows_spot_price = {}
    # To make this a dedicated (non-preemptible) node group instead:
    # - remove the `preemptible = {}` block entirely
    # - remove the `follows_spot_price` block

    
  }
}

// ---- Service and S3 access keys -----------

resource "nebius_iam_v1_service_account" "k8s-jobs-sa" {
  parent_id   = var.project_id
  name        = "k8s-jobs-sa"
  description = "Service account for Kubernetes jobs S3 access"
}

resource "nebius_iam_v1_group_membership" "k8s-jobs-sa-membership" {
  parent_id = var.editors_group_id
  member_id = nebius_iam_v1_service_account.k8s-jobs-sa.id
}

resource "nebius_iam_v2_access_key" "k8s-jobs-key" {
  parent_id   = var.project_id
  name        = "k8s-jobs-key"
  description = "Access key for Kubernetes jobs to use S3"

  account = {
    service_account = {
      id = nebius_iam_v1_service_account.k8s-jobs-sa.id
    }
  }

  secret_delivery_mode = "INLINE"
}

// Not the safest option but works for demo
// Recommended way using mystery box in nebius to store keys

output "storage_access_key_id" {
  value = nebius_iam_v2_access_key.k8s-jobs-key.status.aws_access_key_id
  sensitive = true
}

output "storage_secret_key" {
  value = nebius_iam_v2_access_key.k8s-jobs-key.status.secret
  sensitive = true
}
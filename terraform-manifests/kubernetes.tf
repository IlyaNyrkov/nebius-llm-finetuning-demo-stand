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

resource "nebius_mk8s_v1_node_group" "cpu-small" {
  name      = "cpu-small"
  parent_id = nebius_mk8s_v1_cluster.mlops_stand_k8s.id

  fixed_node_count = 2

  template = {
    resources = {
      platform = "cpu-d3"
      preset   = "2vcpu-8gb"
    }

    os = "ubuntu24.04"

    boot_disk = {
      type           = "NETWORK_SSD"
      size_gibibytes = 64
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

resource "nebius_mk8s_v1_node_group" "gpu-l40s" {
  name      = "gpu-l40s"
  parent_id = nebius_mk8s_v1_cluster.mlops_stand_k8s.id

  autoscaling = {
    min_node_count = 0
    max_node_count = 1
  }

  auto_repair = {}

  template = {
    resources = {
      platform = "gpu-l40s-a"
      preset   = "1gpu-8vcpu-32gb"
    }

    gpu_settings = {
      drivers_preset = "cuda13.0"
    }

    os = "ubuntu24.04"

    boot_disk = {
      type           = "NETWORK_SSD"
      size_gibibytes = 256
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

ephemeral "nebius_iam_v2_access_key_secret" "k8s-jobs-secret" {
  id = nebius_iam_v2_access_key.k8s-jobs-key.id
}

resource "nebius_mysterybox_v1_secret" "k8s-jobs-s3-secret" {
  parent_id   = var.project_id
  name        = "k8s-jobs-s3-secret"
  description = "S3 credentials for k8s jobs"

  sensitive = {
    secret_version = {
      payload = [
        {
          key          = "aws_access_key_id"
          string_value = ephemeral.nebius_iam_v2_access_key_secret.k8s-jobs-secret.aws_access_key_id
        },
        {
          key          = "aws_secret_access_key"
          string_value = ephemeral.nebius_iam_v2_access_key_secret.k8s-jobs-secret.secret
        }
      ]
    }
  }
}
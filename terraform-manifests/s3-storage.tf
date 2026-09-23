resource "nebius_storage_v1_bucket" "mlops-artifacts-bucket" {
  parent_id = var.project_id
  name      = "mlops-artifacts-bucket"
}

resource "nebius_storage_v1_bucket" "mlops-data-bucket" {
  parent_id = var.project_id
  name = "mlops-data-bucket"
}
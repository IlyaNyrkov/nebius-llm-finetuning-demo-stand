variable "project_id" {
  description = "Nebius project ID where resources will be created"
  type        = string
  default     = "project-e00a9ggbpr00wnj4k8dp7h"
}

variable "ssh_public_key" {
  description = "kubernetes ssh public key"
  type        = string
  default     = ""
}

variable "editors_group_id" {
   description = "system id of iam group giving editing rights"
   type = string
   default = "group-e00atz539fjw1ywmb5"
}
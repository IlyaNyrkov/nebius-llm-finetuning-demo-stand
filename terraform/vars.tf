variable "project_id" {
  description = "Nebius project ID where resources will be created"
  type        = string
  default     = "project-e01mmpmepr00aqjvn0xdx7"
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
variable "talos_cluster_name" {
  type = string
  description = "Name of the Talos cluster"
}

variable "talos_image" {
  type = string
  description = "Talos image to load to cluster"
}

variable "talos_config_directory" {
  type = string
  default = "talosconfig"
  description = "Directory name in the root Terraform directory to place Talos configuration"
}

variable "digitalocean_region" {
  type = string
  description = "Human-readable slug of the DigitalOcean region"
}

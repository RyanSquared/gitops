terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

resource "digitalocean_custom_image" "talos" {
  name = "talos"
  url = "https://github.com/siderolabs/talos/releases/download/v1.2.3/digital-ocean-amd64.raw.gz"
  regions = ["sfo3"]
}

module "talos_digitalocean_cluster" {
  source = "./digitalocean"

  talos_image = digitalocean_custom_image.talos.id
  talos_cluster_name = "talos"
  digitalocean_region = "sfo3"
}

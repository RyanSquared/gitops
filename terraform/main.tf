terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

// Has to be manually imported because the one provided by Talos is in a tar
// archive that DigitalOcean throws a fit about.
data "digitalocean_image" "talos" {
  name = "talos"
}

module "talos_digitalocean_cluster" {
  source = "./digitalocean"

  talos_image = data.digitalocean_image.talos.id
  talos_cluster_name = "talos"
  digitalocean_region = "sfo3"
}

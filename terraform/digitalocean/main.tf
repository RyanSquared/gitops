terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

data "digitalocean_region" "provided" {
  slug = var.digitalocean_region
}

resource "digitalocean_ssh_key" "dummy" {
  # DigitalOcean requires a key when deploying an image even if the machine
  # will not have SSH access
  name = "Dummy Talos Key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAseDS76tIQnZyiaBSuZOMI8nixs9NuXqCDGKuv5XPJZ"
}

/*
// Not necessary on single node planes
resource "digitalocean_loadbalancer" "public" {
  name     = "loadbalancer-1"
  region   = "sfo3"

  forwarding_rule {
    entry_port     = 443
    entry_protocol = "tcp"

    target_port     = 6443
    target_protocol = "tcp"
  }

  healthcheck {
    port                     = 6443
    protocol                 = "tcp"
    check_interval_seconds   = 10
    response_timeout_seconds = 5
    healthy_threshold        = 5
    unhealthy_threshold      = 3
  }

  droplet_tag = "talos-digital-ocean-control-plane"

  provisioner "local-exec" {
    command = "sh scripts/init-talos-config.sh ${self.ip}"
  }
}
*/

locals {
  control_plane_patch_labels = "${path.module}/files/control-plane-load-balancer-labels.patch.json"
  control_plane_patch_cni = "${path.module}/files/default-cni.patch.json"
  config_directory = "${path.root}/${var.talos_config_directory}"
}

resource "digitalocean_reserved_ip" "control_plane" {
  region = data.digitalocean_region.provided.slug

  provisioner "local-exec" {
    command = "mkdir -p ${local.config_directory}"
  }
  provisioner "local-exec" {
    command = join(" ", ["talosctl", "gen", "config",
      "--output-dir=${local.config_directory}",
      "--config-patch-control-plane=@${local.control_plane_patch_labels}",
      "--config-patch-control-plane=@${local.control_plane_patch_cni}",
      var.talos_cluster_name,
      "https://${self.ip_address}:6443"
    ])
  }
}

data "local_file" "controlplane" {
  depends_on = [digitalocean_reserved_ip.control_plane]
  filename   = "${local.config_directory}/controlplane.yaml"
}

data "local_file" "worker" {
  depends_on = [digitalocean_reserved_ip.control_plane]
  filename   = "${local.config_directory}/worker.yaml"
}

resource "digitalocean_droplet" "control_plane" {
  name       = "talos-control-plane"
  region     = data.digitalocean_region.provided.slug
  image      = var.talos_image
  size       = "s-2vcpu-4gb"
  user_data  = data.local_file.controlplane.content
  ssh_keys   = [digitalocean_ssh_key.dummy.fingerprint]

  // talos expects the endpoint and node to be that of the machine itself, not the elastic IP
  provisioner "local-exec" {
    command = "talosctl --talosconfig ${local.config_directory}/talosconfig config endpoint ${self.ipv4_address}"
  }

  provisioner "local-exec" {
    command = "talosctl --talosconfig ${local.config_directory}/talosconfig config node ${self.ipv4_address}"
  }

  provisioner "local-exec" {
    # lol
    command = "sleep 30"
  }

  provisioner "local-exec" {
    command = "talosctl --talosconfig ${local.config_directory}/talosconfig bootstrap"
  }
}

resource "digitalocean_reserved_ip_assignment" "control_plane" {
  ip_address = digitalocean_reserved_ip.control_plane.ip_address
  droplet_id = digitalocean_droplet.control_plane.id
}

resource "digitalocean_droplet" "worker" {
  depends_on = [digitalocean_droplet.control_plane]
  count      = 1
  name       = "talos-worker-node-${count.index}"
  region     = data.digitalocean_region.provided.slug
  image      = var.talos_image
  size       = "s-2vcpu-4gb"
  user_data  = data.local_file.worker.content
  ssh_keys   = [digitalocean_ssh_key.dummy.fingerprint]
}

# TODO(RyanSquared): Commenting this part out until I get Kustomizations built
# for all the necessary resources
/*
resource "null_resource" "init-cluster" {
  depends_on = [digitalocean_droplet.worker]

  provisioner "local-exec" {
    command = "sh scripts/init-cluster.sh ${digitalocean_droplet.control-plane[0].ipv4_address}"
  }
}
*/

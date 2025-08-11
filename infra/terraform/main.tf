terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
  credentials = file(var.credentials_file)
}

# Red
resource "google_compute_network" "default" {
  name                    = "hola-net"
  auto_create_subnetworks = true
}

# Firewall HTTP
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.default.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

# Firewall SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.default.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}

# VM con Docker preinstalado
resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network = google_compute_network.default.name
    access_config {} # IP pública
  }

  metadata = {
    ssh-keys                = "${var.ssh_user}:${var.ssh_public_key}"
    metadata_startup_script = file("${path.module}/startup.sh")
  }
}

output "instance_ip" {
  value = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

resource "google_compute_network" "vpc_frontend" {
  name                    = "vpc-frontend"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_backend" {
  name                    = "vpc-backend"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_frontend" {
  name          = "subnet-frontend"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_frontend.id
}

resource "google_compute_subnetwork" "subnet_backend" {
  name          = "subnet-backend"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_backend.id
}

resource "google_compute_network_peering" "frontend_to_backend" {
  name         = "frontend-to-backend"
  network      = google_compute_network.vpc_frontend.self_link
  peer_network = google_compute_network.vpc_backend.self_link
}

resource "google_compute_network_peering" "backend_to_frontend" {
  name         = "backend-to-frontend"
  network      = google_compute_network.vpc_backend.self_link
  peer_network = google_compute_network.vpc_frontend.self_link
}
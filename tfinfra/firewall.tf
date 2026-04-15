# Frontend — SSH and HTTP from anywhere
resource "google_compute_firewall" "frontend_allow_ssh" {
  name          = "frontend-allow-ssh"
  network       = google_compute_network.vpc_frontend.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "frontend_allow_http" {
  name          = "frontend-allow-http"
  network       = google_compute_network.vpc_frontend.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "frontend_allow_icmp" {
  name          = "frontend-allow-icmp"
  network       = google_compute_network.vpc_frontend.name
  source_ranges = ["10.0.2.0/24"]
  allow {
    protocol = "icmp"
  }
}

# Backend — SSH from anywhere
resource "google_compute_firewall" "backend_allow_ssh" {
  name          = "backend-allow-ssh"
  network       = google_compute_network.vpc_backend.name
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Backend — Node.js API (port 3000) from frontend subnet only
resource "google_compute_firewall" "backend_allow_api" {
  name          = "backend-allow-api"
  network       = google_compute_network.vpc_backend.name
  source_ranges = ["10.0.1.0/24"]
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
}

resource "google_compute_firewall" "backend_allow_icmp" {
  name          = "backend-allow-icmp"
  network       = google_compute_network.vpc_backend.name
  source_ranges = ["10.0.1.0/24"]
  allow {
    protocol = "icmp"
  }
}
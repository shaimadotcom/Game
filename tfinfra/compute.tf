resource "google_compute_instance" "vm_backend" {
  name         = "vm-backend"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_backend.id
    access_config {}
  }

  metadata_startup_script = file("${path.module}/backend_setup.sh")
  labels = {
    role = "backend"
  }
}

resource "google_compute_instance" "vm_frontend" {
  name         = "vm-frontend"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_frontend.id
    access_config {}
  }

  metadata_startup_script = file("${path.module}/frontend_setup.sh")

  labels = {
    role = "frontend"
  }
  depends_on = [google_compute_instance.vm_backend]
}

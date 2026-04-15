output "frontend_external_ip" {
  description = "Open this in your browser"
  value       = google_compute_instance.vm_frontend.network_interface[0].access_config[0].nat_ip
}

output "backend_internal_ip" {
  description = "Used by frontend to call the API"
  value       = google_compute_instance.vm_backend.network_interface[0].network_ip
}
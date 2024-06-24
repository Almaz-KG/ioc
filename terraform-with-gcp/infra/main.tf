# Bucket to store website

resource "google_storage_bucket" "website" {
  name     = "blog-almaz-murzabekov-net-bucket"
  location = "EU"
}

# Make new object public
resource "google_storage_object_access_control" "public_rule" {
  object = google_storage_bucket_object.static_site_src.name
  bucket = google_storage_bucket.website.name
  role   = "READER"
  entity = "allUsers"
}

# Upload the index.html file to the bucket
resource "google_storage_bucket_object" "static_site_src" {
  name   = "index.html"
  source = "../website/index.html"
  bucket = google_storage_bucket.website.name
}

# Reserve an external static IP address
resource "google_compute_global_address" "website" {
  name     = "website-lb-ip"
}

# Get the managed DNS Zone
data "google_dns_managed_zone" "dns_zone" {
  name = "terraform-test-almaz-murzabekov-net"
}

# Add the IP to the DNS
resource "google_dns_record_set" "website" {
  name         = "website.${data.google_dns_managed_zone.dns_zone.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [google_compute_global_address.website.address]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "website-backend" {
  name        = "website-backend"
  description = "Contains files needed for the website"
  bucket_name = google_storage_bucket.website.name
  enable_cdn  = true
}

# Create a url map
resource "google_compute_url_map" "website" {
  name            = "website-url-map"
  default_service = google_compute_backend_bucket.website-backend.self_link
    host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.website-backend.self_link
  }
}

resource "google_compute_managed_ssl_certificate" "website" {
    name = "website-cert"
    managed {
      domains = [google_dns_record_set.website.name]
    }
}

# GCP HTTP Proxy
resource "google_compute_target_http_proxy" "website" {
  name     = "website-target-proxy"
  url_map  = google_compute_url_map.website.self_link
}

# GCP HTTPs Proxy
resource "google_compute_target_https_proxy" "website" {
    name = "website-target-proxy"
    url_map = google_compute_url_map.website.self_link
    ssl_certificates = [google_compute_managed_ssl_certificate.website.self_link]
}

# GCP Forwarding rule
resource "google_compute_global_forwarding_rule" "default_http" {
  name                  = "website-forwarding-http-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.website.self_link
}

# GCP Forwarding rule
resource "google_compute_global_forwarding_rule" "default_https" {
  name                  = "website-forwarding-https-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.website.self_link
}

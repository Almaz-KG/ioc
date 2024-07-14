resource "google_storage_bucket" "website" {
    provider = google
    name = "terraform-gcp-example"
    location = "europe-west4"
}

resource "google_storage_bucket_object" "static_site_src" {
    name = "index.html"
    source = "../website/index.html"
    bucket = google_storage_bucket.website.name
}

resource "google_storage_object_access_control" "public_rule" {
    object = google_storage_bucket_object.static_site_src.output_name
    bucket = google_storage_bucket.website.name
    role = "READER"
    entity = "allUsers"
}

resource "google_compute_global_address" "website_ip" {
    provider = google
    name = "website-example-global-ip-address"
}

data "google_dns_managed_zone" "gcp_website_dev" {
    provider = google
    name = "website-example"
}

resource "google_dns_record_set" "website" {
    provider = google
    name = "website.${data.google_dns_managed_zone.gcp_website_dev.dns_name}"
    type = "A"
    ttl = 300
    managed_zone = data.google_dns_managed_zone.gcp_website_dev.name
    rrdatas = [google_compute_global_address.website_ip.address]
}

resource "google_compute_backend_bucket" "website-backend" {
    provider = google
    name = "website-backend"
    description = "Contains files needed by the website"
    bucket_name = google_storage_bucket.website.name
    enable_cdn = true
}

resource "google_compute_managed_ssl_certificate" "website" {
    provider = google-beta
    name = "website-cert"
    managed {
        domains = [google_dns_record_set.website.name]
    }
}

resource "google_compute_url_map" "website" {
  provider = google
  name = "website-url-map"
  default_service = google_compute_backend_bucket.website-backend.self_link
  host_rule {
    hosts = [ "*" ]
    path_matcher = "allpaths"
  }
  path_matcher {
    name = "allpaths"
    default_service = google_compute_backend_bucket.website-backend.self_link
  }
}

resource "google_compute_target_https_proxy" "website" {
    provider = google
    name = "website-target-proxy"
    url_map = google_compute_url_map.website.self_link
    ssl_certificates = [google_compute_managed_ssl_certificate.website.self_link]
}

resource "google_compute_global_forwarding_rule" "default" {
    provider = google
    name = "website-forwarding-rule"
    load_balancing_scheme = "EXTERNAL"
    ip_address = google_compute_global_address.website_ip.address
    ip_protocol = "TCP"
    port_range = "443"
    target = google_compute_target_https_proxy.website.self_link
}
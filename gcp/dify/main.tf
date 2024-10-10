# Complete Dify GCP Terraform Configuration

locals {
  project = "***"  # GCPのプロジェクト名
  region  = "asia-northeast1"
  host    = "xxx.example.com"  # ローカルDifyのドメイン

  dify_version         = "0.8.0"
  dify_sandbox_version = "0.2.7"

  env_vars = [
    { name = "CONSOLE_WEB_URL", value = "https://${local.host}" },
    { name = "CONSOLE_API_URL", value = "https://${local.host}" },
    { name = "APP_WEB_URL", value = "https://${local.host}" },
    { name = "SECRET_KEY", value = "" },
    { name = "DB_USERNAME", value = "" },
    { name = "DB_PASSWORD", value = "" },
    { name = "DB_HOST", value = "" },
    { name = "DB_PORT", value = "6543" },
    { name = "DB_DATABASE", value = "postgres" },
    { name = "MIGRATION_ENABLED", value = "false" },
    { name = "REDIS_HOST", value = "" },
    { name = "REDIS_PORT", value = "" },
    { name = "REDIS_USERNAME", value = "default" },
    { name = "REDIS_PASSWORD", value = "" },
    { name = "REDIS_USE_SSL", value = "true" },
    { name = "REDIS_DB", value = "0" },
    { name = "CELERY_BROKER_URL", value = "" },
    { name = "MAIL_TYPE", value = "resend" },
    { name = "RESEND_API_KEY", value = "" },
    { name = "RESEND_API_URL", value = "https://api.resend.com" },
    { name = "MAIL_DEFAULT_SEND_FROM", value = "noreply@" },
    { name = "STORAGE_TYPE", value = "google-storage" },
    { name = "GOOGLE_STORAGE_BUCKET_NAME", value = "" },
    { name = "GOOGLE_STORAGE_SERVICE_ACCOUNT_JSON_BASE64", value = "" },
    { name = "VECTOR_STORE", value = "pgvector" },
    { name = "PGVECTOR_HOST", value = "" },
    { name = "PGVECTOR_PORT", value = "6543" },
    { name = "PGVECTOR_USER", value = "" },
    { name = "PGVECTOR_PASSWORD", value = "" },
    { name = "PGVECTOR_DATABASE", value = "postgres" },
    { name = "CODE_EXECUTION_API_KEY", value = "" },
    { name = "LOG_LEVEL", value = "INFO" },
    { name = "DEBUG", value = "true" },
    { name = "SENTRY_DSN", value = "" },
  ]
}

provider "google" {
  project = local.project
  region  = local.region
}

# Web Service
resource "google_cloud_run_v2_service" "dify-web" {
  name     = "dify-web"
  location = local.region
  project  = local.project

  template {
    session_affinity = "true"
    max_instance_request_concurrency = 1000
    scaling {
      max_instance_count = 1
      min_instance_count = 0
    }
    containers {
      name  = "web"
      image = "langgenius/dify-web:${local.dify_version}"
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle = "true"
        startup_cpu_boost = "true"
      }
      startup_probe {
        tcp_socket {
          port = 8080
        }
        failure_threshold = 1
        period_seconds    = 240
        timeout_seconds   = 240
      }
      env {
        name  = "CONSOLE_API_URL"
        value = "https://${local.host}"
      }
      env {
        name  = "APP_API_URL"
        value = "https://${local.host}"
      }
      env {
        name  = "SENTRY_DSN"
        value = ""
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "dify-web-member" {
  location = google_cloud_run_v2_service.dify-web.location
  project  = google_cloud_run_v2_service.dify-web.project
  service  = google_cloud_run_v2_service.dify-web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# API Service
resource "google_cloud_run_v2_service" "dify-api" {
  name     = "dify-api"
  location = local.region
  project  = local.project

  template {
    session_affinity = "true"
    max_instance_request_concurrency = 1000
    timeout = "3600s"
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      max_instance_count = 1
      min_instance_count = 1
    }

    containers {
      name  = "api"
      image = "langgenius/dify-api:${local.dify_version}"
      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
        cpu_idle = "true"
        startup_cpu_boost = "true"
      }
      ports {
        container_port = 5001
      }
      startup_probe {
        tcp_socket {
          port = 5001
        }
        failure_threshold = 1
        period_seconds    = 240
        timeout_seconds   = 240
      }
      dynamic "env" {
        for_each = local.env_vars
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env {
        name  = "MODE"
        value = "api"
      }
    }

    containers {
      name  = "worker"
      image = "langgenius/dify-api:${local.dify_version}"
      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle = "false"
        startup_cpu_boost = "true"
      }
      dynamic "env" {
        for_each = local.env_vars
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env {
        name  = "MODE"
        value = "worker"
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "dify-api-member" {
  location = google_cloud_run_v2_service.dify-api.location
  project  = google_cloud_run_v2_service.dify-api.project
  service  = google_cloud_run_v2_service.dify-api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Sandbox Service
resource "google_cloud_run_v2_service" "dify-sandbox" {
  name     = "dify-sandbox"
  location = local.region
  project  = local.project

  template {
    session_affinity = "true"
    max_instance_request_concurrency = 1000

    scaling {
      max_instance_count = 1
      min_instance_count = 0
    }

    containers {
      name  = "sandbox"
      image = "langgenius/dify-sandbox:${local.dify_sandbox_version}"
      ports {
        container_port = 8194
      }
      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle = "true"
        startup_cpu_boost = "true"
      }
      startup_probe {
        tcp_socket {
          port = 8194
        }
        failure_threshold = 1
        period_seconds    = 240
        timeout_seconds   = 240
      }
      env {
        name  = "API_KEY"
        value = ""
      }
      env {
        name  = "GIN_MODE"
        value = "release"
      }
      env {
        name = "WORKER_TIMEOUT"
        value = "100"
      }
      env {
        name = "SANDBOX_PORT"
        value = "8194"
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "dify-sandbox-member" {
  location = google_cloud_run_v2_service.dify-sandbox.location
  project  = google_cloud_run_v2_service.dify-sandbox.project
  service  = google_cloud_run_v2_service.dify-sandbox.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Network Configuration
resource "google_compute_region_network_endpoint_group" "dify-web-neg" {
  name                  = "dify-web-neg"
  network_endpoint_type = "SERVERLESS"
  region                = local.region
  cloud_run {
    service = google_cloud_run_v2_service.dify-web.name
  }
}

resource "google_compute_backend_service" "dify-web-backend-service" {
  name                  = "dify-web-backend-service"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.dify-web-neg.id
  }
}

resource "google_compute_region_network_endpoint_group" "dify-api-neg" {
  name                  = "dify-api-neg"
  network_endpoint_type = "SERVERLESS"
  region                = local.region
  cloud_run {
    service = google_cloud_run_v2_service.dify-api.name
  }
}

resource "google_compute_backend_service" "dify-api-backend-service" {
  name                  = "dify-api-backend-service"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.dify-api-neg.id
  }
}

resource "google_compute_url_map" "dify_url_map" {
  name            = "dify-url-map"
  default_service = google_compute_backend_service.dify-web-backend-service.self_link

  host_rule {
    hosts        = [local.host]
    path_matcher = "path-matcher"
  }

  path_matcher {
    name            = "path-matcher"
    default_service = google_compute_backend_service.dify-web-backend-service.self_link

    path_rule {
      paths   = ["/console/api/*", "/api/*", "/v1/*", "/files/*"]
      service = google_compute_backend_service.dify-api-backend-service.self_link
    }

    path_rule {
      paths   = ["/"]
      service = google_compute_backend_service.dify-web-backend-service.self_link
    }
  }
}

module "lb-http" {
  source  = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version = "~> 11.0"

  project = local.project
  name    = "dify-lb"

  ssl                             = true
  managed_ssl_certificate_domains = [local.host]
  https_redirect                  = true

  backends = {
    default = {
      protocol  = "HTTP"
      port_name = "http"
      enable_cdn = false
      log_config = {
        enable      = true
        sample_rate = 1.0
      }
      groups = [
        {
          group = google_compute_region_network_endpoint_group.dify-web-neg.id
        }
      ]
      iap_config = {
        enable = false
      }
    }
  }

  create_url_map = false
  url_map        = google_compute_url_map.dify_url_map.self_link
}

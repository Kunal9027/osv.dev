locals {
  env_kustomization_path  = "../../../clouddeploy/gke-workers/environments/oss-vdb"
  base_kustomization_path = "../../../clouddeploy/gke-workers/base"
  env_kustomization       = yamldecode(file("${local.env_kustomization_path}/kustomization.yaml"))
  base_kustomization      = yamldecode(file("${local.base_kustomization_path}/kustomization.yaml"))

  all_resources = concat(
    [for resource in local.env_kustomization.resources : "${local.env_kustomization_path}/${resource}" if can(regex("\\.yaml$", resource))],
    [for resource in local.base_kustomization.resources : "${local.base_kustomization_path}/${resource}" if can(regex("\\.yaml$", resource))],
  )

  # Iterate of each yaml configuration and create a key based on kind and name in the yaml file.
  kube_manifests = {
    for manifest in flatten([for file in local.all_resources : yamldecode(file(file))]) :
    "${try(manifest.kind, "")}--${try(manifest.metadata.name, "")}" => manifest
    if try(manifest.kind, "") == "CronJob"
  }
}

module "osv" {
  source = "../../modules/osv"

  project_id = "oss-vdb"

  public_import_logs_bucket                      = "osv-public-import-logs"
  vulnerabilities_export_bucket                  = "osv-vulnerabilities"
  cve_osv_conversion_bucket                      = "cve-osv-conversion"
  debian_osv_conversion_bucket                   = "debian-osv"
  logs_bucket                                    = "osv-logs"
  osv_dev_sitemap_bucket                         = "osv-dev-sitemap"
  backups_bucket                                 = "osv-backup"
  backups_bucket_retention_days                  = 60
  affected_commits_backups_bucket                = "osv-affected-commits"
  affected_commits_backups_bucket_retention_days = 3
  gcs_log_dir                                    = "gs://oss-vdb-tf/apply-logs"

  website_domain = "osv.dev"
  api_url        = "api.osv.dev"
  esp_version    = "2.53.0"
}

module "k8s_cron_alert" {
  for_each                         = local.kube_manifests
  source                           = "../../modules/k8s_cron_alert"
  project_id                       = module.osv.project_id
  cronjob_name                     = each.value.metadata.name
  cronjob_expected_latency_minutes = lookup(each.value.metadata.labels, "cronLastSuccessfulTimeMins", null)
  notification_channel             = "projects/oss-vdb/notificationChannels/17648103713296264012"
}

import {
  to = module.osv.google_firestore_database.datastore
  id = "oss-vdb/(default)"
}

output "website_dns_records" {
  description = "DNS records that need to be created for the osv.dev website"
  value       = module.osv.website_dns_records
}

terraform {
  backend "gcs" {
    bucket = "oss-vdb-tf"
    prefix = "oss-vdb"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.45.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.45.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.2"
    }
  }
}

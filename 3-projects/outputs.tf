output "projects" {
  description = "Factory projects: ID, number, deployer, WIF member (for workload repo CI)."
  value = {
    for key, p in local.projects : key => {
      project_id     = google_project.app[key].project_id
      project_number = google_project.app[key].number
      deployer       = google_service_account.deployer[key].email
      state_bucket   = local.bootstrap.state_buckets[p.env]
      state_prefix   = "${p.app}/${p.env}"
    }
  }
}

output "wif_provider" {
  value = local.bootstrap.wif_provider
}

output "runtime_service_accounts" {
  description = "Runtime service account emails per project/account."
  value       = { for k, sa in google_service_account.runtime : k => sa.email }
}

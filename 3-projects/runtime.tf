# Runtime service accounts for workloads, each with a per-project custom role holding exactly the
# listed permissions. They live here, not in the workload repos, because deployers can't grant IAM
# (no projectIamAdmin). Deployers may still act as them (base role iam.serviceAccountUser).
locals {
  runtime_accounts = merge([
    for key, p in local.projects : {
      for account, permissions in try(p.runtime_accounts, {}) : "${key}/${account}" => {
        project     = key
        account     = account
        permissions = permissions
      }
    }
  ]...)
}

resource "google_service_account" "runtime" {
  for_each = local.runtime_accounts

  project      = google_project.app[each.value.project].project_id
  account_id   = each.value.account
  display_name = "Runtime: ${each.value.account}"
}

resource "google_project_iam_custom_role" "runtime" {
  for_each = local.runtime_accounts

  project     = google_project.app[each.value.project].project_id
  role_id     = "runtime_${replace(each.value.account, "-", "_")}"
  title       = "Runtime ${each.value.account}"
  description = "Only the permissions the ${each.value.account} workload needs (glitch-lz 3-projects)."
  permissions = each.value.permissions
}

resource "google_project_iam_member" "runtime" {
  for_each = local.runtime_accounts

  project = google_project.app[each.value.project].project_id
  role    = google_project_iam_custom_role.runtime[each.key].id
  member  = google_service_account.runtime[each.key].member
}

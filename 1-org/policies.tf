# Org policies. Legacy projects (tag legacy=true) are exempted only where the rule would break
# their existing deploys (CMEK, DRS); everything else applies org-wide.

locals {
  # Boolean constraints enforced org-wide. The first six were set by Google's secure-by-default
  # baseline when the org was created and are imported below.
  enforced_booleans = toset([
    "iam.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.uniformBucketLevelAccess",
    "compute.setNewProjectDefaultToZonalDNSOnly",
    "storage.publicAccessPrevention",
    "compute.skipDefaultNetworkCreation",
    "compute.requireOsLogin",
    "compute.disableSerialPortAccess",
    "sql.restrictPublicIp",
  ])

  baseline_imports = toset([
    "iam.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.uniformBucketLevelAccess",
    "compute.setNewProjectDefaultToZonalDNSOnly",
  ])

  # CMEK required for every service we use that supports it (ADR 033, revised). Autokey keys
  # most of them for free; Firestore, Cloud Run functions (cloudfunctions API) and Cloud Tasks
  # need manual keys from glitch-kms-dev / -prod (2-security). Cloud Logging stays excluded
  # (ADR 011: breaks Error Reporting).
  cmek_services = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudtasks.googleapis.com",
    "compute.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ]
}

import {
  for_each = local.baseline_imports
  to       = google_org_policy_policy.boolean[each.value]
  id       = "${local.org}/policies/${each.value}"
}

resource "google_org_policy_policy" "boolean" {
  for_each = local.enforced_booleans

  name   = "${local.org}/policies/${each.value}"
  parent = local.org

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

import {
  to = google_org_policy_policy.protocol_forwarding
  id = "${local.org}/policies/compute.restrictProtocolForwardingCreationForTypes"
}

resource "google_org_policy_policy" "protocol_forwarding" {
  name   = "${local.org}/policies/compute.restrictProtocolForwardingCreationForTypes"
  parent = local.org

  spec {
    rules {
      values {
        allowed_values = ["INTERNAL"]
      }
    }
  }
}

resource "google_org_policy_policy" "vm_external_ip" {
  name   = "${local.org}/policies/compute.vmExternalIpAccess"
  parent = local.org

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

# europe-west3 only; tag location=eu allows any EU location (ADR 010)
resource "google_org_policy_policy" "resource_locations" {
  name   = "${local.org}/policies/gcp.resourceLocations"
  parent = local.org

  spec {
    rules {
      condition {
        title      = "location=eu"
        expression = local.match_tag["location/eu"]
      }
      values {
        allowed_values = ["in:eu-locations"]
      }
    }
    rules {
      values {
        allowed_values = ["in:europe-west3-locations"]
      }
    }
  }
}

resource "google_org_policy_policy" "cmek_services" {
  name   = "${local.org}/policies/gcp.restrictNonCmekServices"
  parent = local.org

  spec {
    rules {
      condition {
        title      = "legacy=true"
        expression = local.match_tag["legacy/true"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        denied_values = local.cmek_services
      }
    }
  }

  # Exemption tags must be bound before the policy can bite
  depends_on = [google_tags_tag_binding.legacy]
}

# CMEK keys may only come from projects in the Shared folder (Autokey key projects + glitch-iac)
resource "google_org_policy_policy" "cmek_key_projects" {
  name   = "${local.org}/policies/gcp.restrictCmekCryptoKeyProjects"
  parent = local.org

  spec {
    rules {
      values {
        allowed_values = ["under:${google_folder.top["shared"].name}"]
      }
    }
  }
}

# Internal ingress only; tag ingress=public for Firebase-proxied / public services (ADR 013)
resource "google_org_policy_policy" "run_ingress" {
  name   = "${local.org}/policies/run.allowedIngress"
  parent = local.org

  spec {
    rules {
      condition {
        title      = "ingress=public"
        expression = local.match_tag["ingress/public"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        allowed_values = ["is:internal", "is:internal-and-cloud-load-balancing"]
      }
    }
  }

  depends_on = [google_tags_tag_binding.public_ingress]
}

# Filestore Enterprise-tier-only constraint — requested by security to check whether Filestore
# tier can be restricted via org policy. No managed constraint covers this, but the Instance
# resource supports resource.tier as a custom constraint field. Custom constraints are always
# defined at the org (required by the API); scoping enforcement to the DEV folder only, matching
# how DEV/PROD/Shared are already used as the enforcement boundary elsewhere in this stage. Not
# meant to stay enforced: Enterprise is the priciest tier (1 TiB minimum, well over the $10/month
# budget), so leaving this on effectively bans Filestore folder-wide. Demo only — revert after
# security reviews it.
resource "google_org_policy_custom_constraint" "filestore_enterprise_only" {
  name         = "custom.filestoreEnterpriseOnly"
  parent       = local.org
  display_name = "Restrict Filestore to Enterprise tier"
  description  = "Only Filestore Enterprise-tier instances may be created."

  action_type    = "ALLOW"
  condition      = "resource.tier == 'ENTERPRISE'"
  method_types   = ["CREATE"]
  resource_types = ["file.googleapis.com/Instance"]
}

resource "google_org_policy_policy" "filestore_enterprise_only" {
  name   = "${google_folder.top["dev"].name}/policies/${google_org_policy_custom_constraint.filestore_enterprise_only.name}"
  parent = google_folder.top["dev"].name

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "contact_domains" {
  name   = "${local.org}/policies/essentialcontacts.allowedContactDomains"
  parent = local.org

  spec {
    rules {
      values {
        allowed_values = ["@gmail.com"]
      }
    }
  }
}

# Domain-restricted sharing (ADR 012). DRY RUN first: violations are logged, nothing is blocked.
# Promote dry_run_spec to spec once the logs show no unexpected principals.
resource "google_org_policy_policy" "allowed_members" {
  name   = "${local.org}/policies/iam.managed.allowedPolicyMembers"
  parent = local.org

  dry_run_spec {
    rules {
      condition {
        title      = "legacy=true"
        expression = local.match_tag["legacy/true"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedPrincipalSets = ["//cloudresourcemanager.googleapis.com/${local.org}"]
        allowedMemberSubjects = [
          "user:${var.admin_email}",
          "user:${var.kalina_email}",
          # PAM's org-level service agent writes the temporary grants
          "serviceAccount:service-org-${var.org_id}@gcp-sa-pam.iam.gserviceaccount.com",
          # Google system accounts that publish budget alerts to Pub/Sub (kill switch)
          "serviceAccount:billing-budget-alert@system.gserviceaccount.com",
        ]
      })
    }
  }

  depends_on = [google_tags_tag_binding.legacy]
}

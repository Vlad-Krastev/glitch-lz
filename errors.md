# Errors

## ERR-001 — 1-org apply: audit config for iamcredentials.googleapis.com rejected
- **Date:** 2026-09-25
- **Tried:** `google_organization_iam_audit_config` with service `iamcredentials.googleapis.com` (CI apply, run 36129103568)
- **Result:** `Error 400: Service iamcredentials.googleapis.com does not exist or does not support service level configuration of Google Cloud audit logging.` Everything else in 1-org applied.

### Resolution
Service account credential calls (generateAccessToken etc.) are audited under `iam.googleapis.com`;
switched the audit config to that service.

## ERR-002 — PR blocked by code-scanning threads for skipped checkov findings
- **Date:** 2026-09-25 (PR #5)
- **Tried:** upload checkov SARIF as produced
- **Result:** checkov writes `#checkov:skip` findings with SARIF `suppressions`; GitHub code scanning ignores them, opens review threads, and the ruleset (thread resolution required) blocks the merge.

### Resolution
CI strips results that carry `suppressions` before upload (`jq`); threads auto-resolved on the next run.

## ERR-003 — 2-security first apply (run 36131940863): three failures
- **Date:** 2026-09-25
- **a)** `google_project_service_identity` (cloudkms) returns the **EKM** agent `service-N@gcp-sa-ekms`; binding it failed "does not exist". Autokey needs `service-N@gcp-sa-cloudkms`.
- **b)** Pub/Sub topic creation: "Cloud Pub/Sub API has not been used in project glitch-iac" — provider-level `billing_project = glitch-iac` + `user_project_override` sent every call with glitch-iac as quota project.
- **c)** `google_monitoring_monitored_project` 403: `monitoring.metricsScopes.link` is required on the scoping **and** the monitored project; lz-apply only had monitoring.admin on glitch-monitoring.

### Resolution
- a) Bind `service-${project_number}@gcp-sa-cloudkms.iam.gserviceaccount.com` (as in Google's Autokey Terraform example).
- b) ~~Removed the provider-level quota-project override~~ — **did not work** (run 36140137823, same error for consumer project 364574903782 = glitch-iac): calls made as lz-apply in CI are attributed to the SA's own project regardless. Real fix: enable `pubsub.googleapis.com` in glitch-iac (0-bootstrap `local.services`), consistent with glitch-iac being the quota project for every LZ API. Rule: when a stage starts using a new API, add it to 0-bootstrap's list.
- c) `roles/monitoring.metricsScopesAdmin` at org for lz-apply (0-bootstrap, human-applied).

## ERR-004 — 0-bootstrap local plan hangs (cloudbilling 429)
- **Date:** 2026-09-25
- **Tried:** local `terraform plan` (admin ADC) on the kill-switch branch; first attempt hung >5 min and left a stale lock after SIGINT/TERM; retry with `timeout 200` hung the same way.
- **Result:** TF_LOG showed `google_billing_account_iam_member` reads retrying on `429 RATE_LIMIT_EXCEEDED` for consumer `projects/764086051850` — the shared Google Cloud SDK project, not ours (user credentials sent no quota project to this API). Stale locks removed with `terraform force-unlock <generation>` (GCS lock ID = object generation, not the UUID in the lock file).

### Resolution
0-bootstrap provider sets `billing_project = glitch-iac` + `user_project_override = true` (only this stage runs with user credentials; CI SAs bill to glitch-iac anyway).


## ERR-005 — 1-org apply: PAM org service agent does not exist
- **Date:** 2026-09-26 (run 36194498987)
- **Tried:** `google_organization_iam_member` granting `roles/privilegedaccessmanager.serviceAgent` to `service-org-<org>@gcp-sa-pam.iam.gserviceaccount.com` right after enabling the PAM API.
- **Result:** `Error 400: Service account service-org-***@gcp-sa-pam.iam.gserviceaccount.com does not exist.` Org-level service agents are created on demand; enabling the API in glitch-iac doesn't create it. 2-security / 3-projects applies were cancelled.

### Resolution
Ran `gcloud pam check-onboarding-status --organization=<org> --location=global --billing-project=glitch-iac` once (the call behind the console's "Set up PAM"); it provisioned the agent, and the re-run applied. For a fresh org: run it before the first 1-org apply.

## ERR-006 — AR custom constraint: `resource.mode == 'VIRTUAL'` doesn't match virtual repos
- **Date:** 2026-11-05 (PR #31, test in `glitch-ops-dev`)
- **Tried:** `custom.arCmekExceptVirtual`, ALLOW on CREATE, condition
  `resource.mode == 'VIRTUAL' || resource.kmsKeyName != ''` (the `'VIRTUAL'` spelling is from the
  Artifact Registry custom-constraint docs).
- **Result:** keyless virtual repo create denied: `Operation denied by org policy ... customConstraints/custom.arCmekExceptVirtual`.
  Keyless standard/remote denied (expected), standard with key allowed (expected), so the
  `kmsKeyName` half works and the mode comparison is what fails.
- **Also seen:** right after the apply, the old `gcp.restrictNonCmekServices` deny still applied
  for ~1 min, although the effective policy already showed AR removed. Propagation delay, not a bug.

unresolved

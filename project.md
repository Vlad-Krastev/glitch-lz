# glitch-lz

Terraform landing zone for the Glitch GCP organization: org policies, tags, folders, org IAM,
logging, KMS / Autokey, budgets and the project factory. Workloads live in their own repos and
consume hardened modules from [`glitch-modules`](https://github.com/Vlad-Krastev/glitch-modules).

Priorities, in order: **cost > security > availability**. Hard ceiling ≤ $10/month for everything;
a traffic flood must degrade a service, never grow the bill.

## Layout

| Stage | Contents |
|---|---|
| `0-bootstrap` | `glitch-iac` project, state buckets (`-lz`, `-dev`, `-prod`), LZ deployer SA, GitHub WIF pool. Applied once locally, then state migrated into its own bucket |
| `1-org` | Org policies, tag keys / values, folders (imported), org IAM, audit log config, essential contacts |
| `2-security` | KMS projects + Autokey, logging project + org sink, monitoring scope, billing-account budget |
| `3-projects` | Project factory: `glitch-<app>-<env>` projects, APIs, deployer SAs, WIF bindings, budgets, quotas |
| `4-network` | Only when a workload needs a VPC |

Each stage is its own root module and state (prefix = stage name in `glitch-tfstate-lz`).

## Conventions

- Region `europe-west3`; labels `env`, `app`, `owner`, `managed_by=terraform`.
- Trunk-based: `main` only, feature branches → PR. Environment differences only in tfvars.
- Real IDs (org, billing account, admin email) never in Git: local `terraform.tfvars` (ignored) or
  GitHub Actions variables. Commit `*.tfvars.example` instead.
- Pre-commit hook (`.githooks/pre-commit`, enabled via `git config core.hooksPath .githooks`)
  runs `gitleaks` and `terraform fmt`.

## Decisions & Notes

Full design and ADRs 001–024 are in the private design doc (ClickUp, Landing Zone space →
"Landing Zone Design"). Decisions taken in this repo:

- ADR 025: Repos `glitch-lz` / `glitch-modules` are **public** | Reason: portfolio visibility, and on
  free GitHub only public repos get enforced rulesets, environment reviewers, secret scanning and
  push protection | Tradeoffs: rejected private (no enforced guardrails on free plan) and GitHub Pro
  (cost). Consequences: no secrets or real IDs in Git, WIF pinned to repo/owner IDs + ref, no
  `pull_request_target`, no self-hosted runners, plans not posted to PRs.
- ADR 026: State buckets in `0-bootstrap` are encrypted with Autokey keys stored in `glitch-iac`
  itself — same-project key storage configured on the **Shared folder** (the provider only supports
  folder-level Autokey config), so all Shared projects keep their own keys; DEV / PROD use the
  dedicated key projects from 2-security | Reason: Autokey keys are in the free tier (100 key versions,
  10k ops/month), manual keys are $0.06/version/month; the LZ state must not depend on key projects
  that a later stage manages | Tradeoffs: rejected Google-managed encryption (breaks the CMEK rule)
  and manual keys in glitch-iac (cost).
- ADR 027: Default branch `main`, commits authored with the GitHub noreply address | Reason: matches
  the design (trunk-based on `main`); keeps personal email out of public history.
- ADR 028: Two LZ identities — `lz-plan` (read-only, env `lz-plan`, PRs) and `lz-apply` (env
  `lz-apply` + `refs/heads/main`, enforced in the WIF binding). Every GCP-authenticating job declares
  a GitHub environment | Reason: least privilege for PR plans on a public repo; main-only apply
  enforced on the GCP side too | Tradeoffs: rejected one SA for plan and apply.
- ADR 029: PR gates `fmt -check`, `validate`, `tflint`, `checkov`, `plan`, summarised by one required
  check `ci-ok`; local hook runs only `gitleaks` + `fmt`; all actions pinned by SHA, kept current by
  Dependabot | Reason: fast commits, full checks before merge, supply-chain safety | Tradeoffs:
  rejected trivy (fewer GCP rules), the checkov GitHub action (ships an outdated image).
- ADR 030: Planner uses curated read-only roles instead of `roles/viewer`; apply SA has no
  `roles/iam.securityAdmin` (3-projects grants SA admin per adopted project); Data Access audit logs
  on glitch-iac replace bucket access logs | Reason: checkov CKV_GCP_115 / 45 / 62 | Tradeoffs:
  planner roles must be extended when a new stage's plan hits a 403.
- ADR 031: Pre-LZ projects (`vk-personal-dashboard`, `wedding2026-vk`) are tagged `legacy=true` and
  exempt from the CMEK and DRS policies; location / ingress / baseline policies still apply | Reason:
  keep live apps deployable without rework; exemption is removed when a project is rebuilt in the
  factory | Tradeoffs: rejected enforcing everything (breaks wedding source deploys) and a separate
  Legacy folder (touches IAM inheritance).
- ADR 032: DRS (`iam.managed.allowedPolicyMembers`) starts in dry run; other new policies are
  enforced immediately | Reason: service-agent exceptions for the managed constraint are poorly
  documented; all other policies only affect resource creation and every non-legacy project already
  complies | Tradeoffs: a window where DRS only logs.
- ADR 033 (revised 2026-09-25): CMEK required for every used service that supports it — Artifact
  Registry, BigQuery, Cloud Run, Cloud Run functions, Cloud SQL, Cloud Tasks, Compute, Firestore,
  Pub/Sub, Secret Manager, Storage; keys only from projects under Shared | Reason: owner requirement;
  Autokey covers most for free, manual keys (Firestore, functions, Tasks) cost ~$0.36/month for dev +
  prod | Tradeoffs: Cloud Logging excluded (ADR 011); functions deployed via Cloud Run to use Autokey;
  `gcloud run deploy --source` / Firebase-console resource creation unusable in new projects.
- ADR 034: IDs are looked up with data sources (folders by display name, projects by ID) instead
  of committed or passed as secrets | Reason: public repo, fewer CI secrets.
- ADR 035: Every project gets a $10/month budget (supersedes ADR 022's per-project sizes); the
  billing-account budget is $10 with alerts at 50–200 %. Dev projects: kill switch detaches billing
  at 100 % of their own budget (per project, not per folder); prod: alert only until the kill
  switch is tested, then at a multiple; Shared: alert only | Reason: $1–5 tripwires would be noise;
  per-project kill switch contains a runaway without touching other projects; realistic worst case
  ≈ $10–15 per runaway dev project given hours of budget-data lag | Tradeoffs: budgets don't cap —
  max_instances, quotas and auth-before-container remain the hard limits.
- ADR 036: Manual CMEK keys (Firestore, Cloud Tasks, Cloud Run functions) rotate yearly, not every
  90 days | Reason: every version bills $0.06/month and must stay while data uses it | Tradeoffs:
  checkov CKV_GCP_43 skipped.
- ADR 037: No Data Access audit logs on the key projects | Reason: every workload encrypt/decrypt
  would be logged, turning a traffic flood into a logging bill (ADR 021) | Tradeoffs: admin
  activity on keys is still always logged; CKV2_GCP_5 skipped for those projects.
- ADR 038: One deployer SA per workload project; dev federation accepts any ref in environment
  `dev` (PRs plan dev), prod only environment `prod` on `refs/heads/main` | Reason: simple, prod
  gated on the GCP side too | Tradeoffs: PRs can't plan prod — prod is planned in the promotion job;
  a read-only prod planner can be added later.
- ADR 039: Workload state isolation per prefix: custom role `tfStateLister` (objects.list,
  buckets.get) unconditionally + `objectUser` conditioned on `<app>/<env>/` | Reason: the GCS backend
  must list, and IAM conditions can't scope list calls | Tradeoffs: deployers see other apps' state
  object names (not contents) in the same env bucket.
- ADR 040: Legacy projects get budget + metrics scope via data sources, not imported as
  `google_project` | Reason: importing would let Terraform change live apps' labels / settings |
  Tradeoffs: full adoption deferred to their rebuild.
- ADR 041: No Data Access audit logs on workload projects | Reason: IAP authz and Storage reads log
  per request — a flood becomes a logging bill (ADR 021) | Tradeoffs: CKV2_GCP_5 skipped.
- ADR 042: Kill switch = Cloud Run service (stdlib Python, pinned public image via CMEK Docker Hub
  proxy) behind a Pub/Sub push subscription; billing rights only on the DEV folder; starts with
  `ENFORCE=false` | Reason: no build pipeline or dependencies to maintain; IAM, not code, decides
  which projects can be killed | Tradeoffs: rejected Cloud Functions API (needs manual CMEK key,
  ADR 033).
- ADR 043: 0-bootstrap's provider sets glitch-iac as quota project | Reason: admin credentials
  otherwise hit the shared Cloud SDK project's exhausted billing-API quota (ERR-004).
- ADR 045: Second operator (Kalina, Gmail) has standing read-only access (browser, security
  reviewer, logging/monitoring/org-policy/PAM/tag viewers) and elevates with PAM: DEV `roles/writer`
  self-service (8h); PROD `roles/writer` and org `organizationAdmin` approved by Vlad (2h).
  `roles/writer` has no IAM-admin permissions, so a grant can't create permanent access. Vlad keeps
  his standing super-admin roles for now (break-glass, outside Terraform). Nobody impersonates
  lz-apply; both may impersonate lz-plan | Reason: least privilege + approval for the second
  operator without lock-out risk | Tradeoffs: rejected Cloud Identity (org isn't bound to a
  directory; a new org would be needed) and org-level `roles/viewer` (basic role, reads data).

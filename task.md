# Tasks

Mirrors the ClickUp "GlitchLZ — implementation" task (Vladimir space).

| Task | Status | Notes |
|---|---|---|
| Repo guardrails (.gitignore, gitleaks hook, rulesets, security settings) | done | |
| Stage 0-bootstrap | done | Applied 2026-09-25 (56 resources); state in `glitch-tfstate-lz/0-bootstrap` |
| Stage 1-org | done | Applied 2026-09-25; CMEK list 11 services; DRS in dry run |
| Stage 2-security | done | KMS projects + Autokey + manual keys, security log sink, monitoring, $10 budgets. Also fix Cost page budget section in the ClickUp design doc (ADR 035) |
| Stage 3-projects | done | Factory + first app `ops` (GlitchOps); legacy projects budget + metrics scope only |
| Stage 4-network | pending | Optional |
| CI: GitHub Actions + WIF for glitch-lz | done | PR gates: fmt, validate, tflint, checkov, plan (lz-plan SA); apply via env `lz-apply`. Plans not posted to PRs (public logs) |
| Promote DRS from dry run to enforced | pending | After reviewing dry-run violations |
| Remove legacy tags | pending | wedding: when retired/rebuilt; GlitchHub dev: after prod promotion + dev teardown |
| Dev kill switch (budget-alerts → detach billing) | done | Enforcing; tested: prod → 403, dev → detached + re-linked, no drift |
| VPC-SC dry-run perimeter | pending | Once internal workload projects exist |
| Delete old GlitchHub $5 budget | done | |
| Operators + PAM (ADR 045) | done | Kalina: read-only + PAM (dev self, prod/org approved by Vlad); entitlements visible to her. Vlad unchanged |
| Onboarding docs for operators (CONTRIBUTING / repo CLAUDE.md) | done | #14; app template + setup script come with the wiki |
| Filestore Enterprise-only constraint demo (DEV folder) | done | #16; tested 2026-09-30: `BASIC_HDD` create in `glitch-ops-dev` denied (`CUSTOM_ORG_POLICY_VIOLATION`). Kept enforced (ADR 046) |

## Handoff

- LZ: stages 0–3 live, kill switch enforcing, PAM for Kalina. Next LZ items: DRS dry-run review → enforce; VPC-SC later.
- GlitchOps: projects + GitHub envs ready; next: SSG choice, ClickUp export, first glitch-modules, CI.

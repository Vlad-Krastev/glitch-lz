# The project factory input. One entry per app; each app gets a dev and a prod project.
# Nothing here is secret (public repo, ADR 025): GitHub repo IDs are public.
locals {
  apps = {
    # GlitchOps: docs-as-code wiki — Firebase Hosting (custom domains) → Cloud Run login server
    # with Firebase Auth (glitch-ops ADRs; content in a private repo)
    ops = {
      repo_id = "1387711334"
      # Firebase Hosting rewrites need ingress "all"; the login server authenticates every request
      public_ingress = true
      apis = [
        "artifactregistry.googleapis.com",
        "firebase.googleapis.com",
        "firebasehosting.googleapis.com",
        "identitytoolkit.googleapis.com",
        "run.googleapis.com",
      ]
      roles = [
        "roles/artifactregistry.admin",
        "roles/firebase.viewer",
        "roles/firebasehosting.admin",
        "roles/identityplatform.admin",
        "roles/run.admin",
      ]
      # Created here because the deployer can't grant IAM: the wiki server may only mint
      # Firebase session cookies.
      runtime_accounts = {
        wiki-server = ["firebaseauth.users.createSession"]
      }
    }
  }

  # Pre-LZ projects: budget + metrics scope only, not managed as project resources (ADR 040)
  legacy_projects = {
    glitchhub-dev = "vk-personal-dashboard"
    wedding-prod  = "project-a60d576f-3d59-42e0-b1f"
  }
}

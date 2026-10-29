# Setup

Two parts: getting a machine ready to work on this repo (every machine), and bootstrapping the GCP project (once, ever). Day-to-day commands are in the README's [Development & Deployment](../README.md#development--deployment) section.

## 1. Install the tools

| Tool | Version | Why |
|---|---|---|
| git | any | |
| Google Cloud CLI (`gcloud`, `bq`) | current | Auth, running jobs, querying BigQuery |
| Terraform | **1.14.3** exactly | Matches CI (`.github/workflows/ci.yml`) |
| Python | **3.13** | Matches every image ([0006](decisions/0006-runtime-versions.md)). macOS's built-in `python3` is 3.9 and too old |
| Docker Desktop | current | Running Python 3.13 or dbt without installing them |
| GitHub CLI (`gh`) | optional | Watching CI runs from the terminal |

## 2. Get the code and a Python environment

```bash
git clone https://github.com/tylerjclifton/new-england-grid-analytics.git
cd new-england-grid-analytics
python3.13 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt        # every component plus ruff, sqlfluff, pytest
```

**No Python 3.13 locally?** Run anything inside a container instead, for example:

```bash
docker run --rm -v "$PWD":/repo -w /repo python:3.13-slim sh -c \
  "pip install -q -r requirements.txt && ruff check ingest transform && pytest"
```

## 3. Sign in to Google Cloud

This project has its own GCP project, `new-england-grid-analytics`, separate from mbta-reliability-analytics. Give it its own gcloud configuration rather than switching another one:

```bash
gcloud config configurations create grid
gcloud config set account <your google account>
gcloud config set project new-england-grid-analytics
gcloud auth login
gcloud auth application-default login              # credentials for dbt, Terraform, and Python clients
```

`gcloud config configurations activate <name>` switches between projects. Application-default credentials are shared by every configuration; the environment variables below (and `project` in `transform/profiles.yml`) say which project to use.

## 4. Terraform

```bash
cd infra && terraform init        # state lives in GCS (README, "Terraform state")
```

A local plan needs two things CI provides automatically:

```bash
USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=new-england-grid-analytics \
  terraform plan -var image_tag=$(git rev-parse --short=12 origin/main)
```

- `image_tag` has no default on purpose. Plan against the commit that's deployed ([0005](decisions/0005-deploy-only-through-ci.md)).
- The two environment variables give your local credentials a quota project.
- Don't `apply` locally. Push to `main` and CI applies ([0004](decisions/0004-terraform-only-changes.md), [0005](decisions/0005-deploy-only-through-ci.md)). The bootstrap below is the one exception.

## 5. Check that everything works

```bash
ruff check ingest transform && pytest                                  # Python
(cd transform && dbt parse --profiles-dir . && sqlfluff lint models)   # SQL
(cd infra && terraform fmt -check -recursive && terraform validate)    # Terraform
```

These are the same checks CI runs. If they pass, you're set up.

---

## Bootstrap (once per project)

CI can't deploy until its Google identity and the Terraform state bucket exist, and Terraform creates both. So the first apply runs from a workstation ([0005](decisions/0005-deploy-only-through-ci.md)). It creates only what CI needs; CI's first deploy creates everything else, once it has built the images the jobs run.

The project itself (`new-england-grid-analytics`, number 987931704118) was created and linked to the billing account by hand on 2026-10-29.

**1. Budget alerts** ([0003](decisions/0003-cost-guardrails.md)):

```bash
gcloud billing budgets create --billing-account=<ACCOUNT_ID> \
  --display-name="New England grid — \$5/month guardrail" --budget-amount=5USD \
  --filter-projects=projects/new-england-grid-analytics \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
  --threshold-rule=percent=1.0,basis=forecasted-spend \
  --threshold-rule=percent=2.0 --threshold-rule=percent=4.0
```

(`gcloud billing projects describe new-england-grid-analytics` shows the account ID.)

**2. Local-state apply of CI's prerequisites.** In `infra/main.tf`, comment out the `backend "gcs"` block, then:

```bash
cd infra && terraform init
export USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=new-england-grid-analytics

# APIs first: the identity resources below need IAM, STS, and Artifact Registry enabled
terraform apply -var image_tag=bootstrap -target=google_project_service.api

# The state bucket, the image repository, and CI's identity with its roles
terraform apply -var image_tag=bootstrap \
  -target=google_storage_bucket.tfstate \
  -target=google_artifact_registry_repository.repo \
  -target=google_iam_workload_identity_pool_provider.github \
  -target=google_service_account_iam_member.github_deployer_wif \
  -target=google_project_iam_member.github_deployer \
  -target=google_storage_bucket_iam_member.github_deployer_tfstate
```

`image_tag=bootstrap` is a placeholder: none of the targeted resources use it.

**3. Move state into the bucket.** Restore the `backend "gcs"` block, then `terraform init -migrate-state` and answer yes. Delete the local `terraform.tfstate*` files once `terraform state list` works.

**4. First deploy.** Push to `main`. CI builds the images and applies everything else. Then seed bronze and push the models (README, "Development & Deployment"; [0005](decisions/0005-deploy-only-through-ci.md)): the first push carries no dbt sources, so the transform's freshness check has nothing to fail on.

---

## Things that live outside the repo

None of these are in code, and some lapsing would stop the pipeline with no alert:

| What | Where | Notes |
|---|---|---|
| **GCP billing account** | Cloud Console → Billing | Shared with mbta-reliability-analytics. The payment card must stay valid, or both projects stop |
| **$5/month budget** | Billing → Budgets | Created with `gcloud billing budgets` (above); alerts only ([0003](decisions/0003-cost-guardrails.md)) |
| **ISO Express account** | iso-ne.com | Its login is the `isone-ws-username` / `isone-ws-password` secrets ([runbook](runbook.md#add-or-rotate-a-source-credential)) |
| **EIA API key** | eia.gov/opendata | The `eia-api-key` secret |
| **Open-Meteo terms** | open-meteo.com | Free for non-commercial use, 10,000 calls/day; this project makes 4 |
| **GitHub `production` environment** | Repo settings → Environments | The deploy job runs in it (created by the first deploy) |
| **Failure-alert email** | `alert_email` in `infra/variables.tf` | In code; listed here so it isn't forgotten |

# Build Log – how this project was built, step by step

This is the "lab notebook" for the project: **what** was done, **why**, **how to verify it**, and the **gotchas**
that were found along the way. Read it in order and you can explain the whole build in an interview.

> Companion documents: [README](../README.md) (how to run it) · [INTERVIEW-GUIDE](INTERVIEW-GUIDE.md) (Q&A and talking points).

---

## 0. Starting point – what the repo was

| Item | Finding | Consequence |
|---|---|---|
| `backend/` | Spring Boot 3.2.0, Java 17, one endpoint `GET /movies` on port 8080, Dockerfile expected a **pre-built jar** | Dockerfile only worked after a separate `mvn package` (Jenkins did that) |
| `frontend/` | static HTML/JS/CSS + images, nginx **as root** on port 80 | fails the "run as non-root" standard |
| `frontend/app.js` | API URL **hard-coded** to `http://65.2.3.52:8080/movies` (an old EC2 IP) | would break on any new environment |
| `MovieController` | `@CrossOrigin(origins = "*")` | needed only because front and back were on different hosts/ports |
| `Jenkinsfile` | Build, Sonar, dependency-check, frontend docker build | kept unchanged (you asked to keep it) |
| Infrastructure | none | everything below is new |

Target (from the requirements): *push repo → run the Action → AWS resources are provisioned → app runs on EKS, with
guardrails, and documentation a beginner can follow.*

---

## 1. Design decisions (made before writing any code)

| # | Decision | Why | Alternative considered |
|---|---|---|---|
| 1 | **Region `ap-south-1` (Mumbai)** | The old hard-coded IP and your location point there; lowest latency for you | any region – it is one variable |
| 2 | **EKS Kubernetes 1.35** | Checked the AWS docs: 1.34–1.37 are in *standard* support. 1.33 and older are in **extended support, which costs extra per cluster-hour**. 1.35 is mature (released Jan 2026, supported until Mar 2027) | 1.37 (newest, fewer add-on versions proven) |
| 3 | **GitHub → AWS via OIDC**, not access keys | Keys leak; OIDC tokens last minutes and are tied to repo + environment | stored `AWS_ACCESS_KEY_ID` secrets (rejected) |
| 4 | **Two IAM roles**: `plan` (read-only) and `deploy` (scoped) | Least privilege: a PR can never change anything | one admin role |
| 5 | **A separate `bootstrap/` stack** | Chicken-and-egg: Actions needs a role + state bucket that must exist *before* it can run | create them by hand in the console (not reproducible) |
| 6 | **Terraform state in S3 with native locking** (`use_lockfile`, Terraform ≥ 1.10) | Shared, encrypted, versioned state; no DynamoDB table to manage | local state; S3 + DynamoDB lock |
| 7 | **Community modules** `terraform-aws-modules/vpc` and `/eks` (exact versions pinned) | Battle-tested, readable, what most teams use | hand-written resources (much longer, more mistakes) |
| 8 | **Private nodes + 1 NAT gateway** | Servers have no public IPs; one NAT keeps cost down (~USD 32–41/mo) | VPC endpoints (more setup), NAT per AZ (HA, 2× cost) |
| 9 | **Managed node group, 2× `t3.medium`, AL2023** | Simple, AWS patches/rolls the nodes; t3.medium fits the system pods + app | Fargate, Karpenter, Auto Mode |
| 10 | **ALB via the AWS Load Balancer Controller (Ingress)**, `target-type: ip` | One load balancer routes `/movies` → backend and `/` → frontend on the **same origin** (no CORS) | NodePort / classic LB per service |
| 11 | **IRSA** for the controller's AWS permissions | Only that one Kubernetes service account can assume the role | node-role permissions (too broad) |
| 12 | **EKS access entries** (`authentication_mode = "API"`) | Modern IAM-native access, no `aws-auth` ConfigMap to corrupt | `aws-auth` ConfigMap |
| 13 | **Kustomize** for manifests | Built into `kubectl`; lets CI swap image tags | Helm chart for the app (heavier) |
| 14 | **Builds inside Docker** (multi-stage) | CI needs no Java installed and tests run during the image build. Also sidesteps your rule about internal `lmigtech/internal-actions/setup-*` actions, which a *personal* repo cannot access | `actions/setup-java` + Maven |
| 15 | **Manual `workflow_dispatch` deploy** | Nothing can start costing money from an accidental push | deploy on every push to `main` |

---

## 2. Tooling check and version research

Done first so nothing is built from stale memory.

- Verified which tools were on your machine: Docker (Rancher Desktop), kubectl, Helm, Node, Python. **Not** installed: Terraform, AWS CLI, Java, Maven.
- Downloaded a **portable Terraform 1.17.1** into the session folder (no system changes) so the code could be validated for real.
- Looked up the current versions and pinned them:

  | Component | Version |
  |---|---|
  | Terraform | 1.17.1 |
  | AWS provider | 6.71.0 (`~> 6.0`, locked in `.terraform.lock.hcl`) |
  | VPC module | 6.7.3 |
  | EKS module | 21.29.0 |
  | AWS Load Balancer Controller chart/app | 3.6.2 |
  | Spring Boot (parent) | 3.5.16 |

- Downloaded the **official IAM policy** for the Load Balancer Controller at the matching tag into
  `infra/policies/aws-load-balancer-controller-iam-policy.json` (never hand-write this one).

**Lesson:** the EKS module v21 renamed many inputs from v20 (`cluster_name` → `name`, `cluster_version` →
`kubernetes_version`, `cluster_addons` → `addons`, …). I ran `terraform init` first and **read the real variable
definitions** instead of guessing. Always check module docs for the exact version you pin.

---

## 3. Application changes (so it can run on Kubernetes)

| File | Change | Reason |
|---|---|---|
| [backend/Dockerfile](../backend/Dockerfile) | **Multi-stage**: stage 1 `mvn clean verify` (compiles + tests), stage 2 minimal JRE; runs as **uid 10001** | self-contained build, small image, non-root |
| [backend/pom.xml](../backend/pom.xml) | Spring Boot parent 3.2.0 → **3.5.16** | 3.2.0 ships an old Tomcat/Spring with known HIGH/CRITICAL CVEs that would fail the image scan gate |
| [MovieController.java](../backend/src/main/java/com/netflixclone/catalog/controller/MovieController.java) | removed `@CrossOrigin("*")` | front and back now share one origin through the ALB; open CORS is a needless exposure |
| [frontend/app.js](../frontend/app.js) | `API_URL` → relative `"/movies"` | no environment-specific IP in code |
| [frontend/Dockerfile](../frontend/Dockerfile) | `nginxinc/nginx-unprivileged`, port **8080**, `USER 101`, copies only the site files + `images/` | non-root nginx (root can't bind port 80 anyway in a restricted pod) |
| [frontend/nginx.conf](../frontend/nginx.conf) | new: security headers, hides nginx version | hardening |
| `.dockerignore` (both) | new | smaller build context, no junk in images |

**How it was verified (locally, with Docker):**

1. Built both images.
2. Ran them with the **same restrictions Kubernetes will apply**:
   `--read-only --tmpfs /tmp --user <uid> --cap-drop ALL --security-opt no-new-privileges`.
3. Frontend: `GET /` → 200, security headers present, `/images/...png` → 200.
4. Backend: Maven build + tests passed inside the image build; `/movies` returned the 3 movies within ~6 s, with a 512 MB memory limit.

**Gotcha caught:** my first frontend Dockerfile copied only `index.html app.js style.css`. The movie JSON contains
`/images/...` paths, so the images folder would have been missing. Found it by looking at the full file tree and fixed it.
(My first file listing had excluded `*.png`/`*.jpg` – check your filters!)

---

## 4. Terraform – `bootstrap/` (one-time, local state)

Files: `versions.tf`, `variables.tf`, `main.tf`, `iam.tf`, `budget.tf`, `outputs.tf`.

1. **State bucket** – S3 with versioning, **KMS (customer-managed, rotating key)** encryption, public-access block, ACLs disabled,
   a bucket policy that **denies non-TLS access**, lifecycle rules (old versions expire after 90 days), `force_destroy = false`.
2. **GitHub OIDC identity provider** (`token.actions.githubusercontent.com`) – optional because an account may only have one.
3. **Plan role** `netflix-github-plan` – trust: `repo:OWNER/REPO:pull_request` and `…:ref:refs/heads/*`.
   Permissions: AWS-managed `ReadOnlyAccess` + read state + write **only** the `*.tflock` lock object + use the state KMS key.
4. **Deploy role** `netflix-github-deploy` – trust: **only** `repo:OWNER/REPO:environment:production`, session up to 2 h.
   Permissions are service-scoped, and IAM is limited to resources named `netflix-*`. Two explicit **Deny** statements:
   - it cannot modify `netflix-github-*` roles (stops self-escalation),
   - nothing outside the chosen region.
   An escape hatch `deploy_role_admin_access` exists for debugging `AccessDenied` (default `false`).
5. **AWS Budget** with email alerts at 50 % / 80 % actual and 100 % forecast.
6. **Outputs** include ready-to-paste `gh variable set …` commands.

Why local state here? The bucket that would hold remote state doesn't exist yet. The tiny bootstrap state is
kept locally (git-ignored).

---

## 5. Terraform – `infra/` (the real platform)

| File | What it builds | Key guardrails |
|---|---|---|
| `versions.tf` | provider/Terraform pins + **partial S3 backend** (bucket/region/KMS key injected at `init`) | `encrypt`, `use_lockfile` |
| `providers.tf` | AWS provider + **default tags** (Project, Environment, ManagedBy, Repository) | cost allocation, ownership |
| `variables.tf` | all inputs with **validation blocks** | `node_max_size ≤ 6` (cost cap), `az_count` 2–3, name format |
| `main.tf` | data lookups + locals (AZs, subnet CIDRs, admin map) | subnets: private /20 ×2, public /24 ×2 |
| `network.tf` | VPC module | private nodes, 1 NAT, **default SG locked**, **flow logs**, ELB subnet tags |
| `eks.tf` | EKS module | see below |
| `ecr.tf` | 2 ECR repos + lifecycle | **immutable tags**, scan on push, KMS encryption, keep last 20 |
| `iam-lbc.tf` | IRSA role for the Load Balancer Controller | trust limited to `kube-system/aws-load-balancer-controller` |
| `outputs.tf` | cluster name, VPC id, role ARN, ECR URLs | consumed by the pipeline |
| `tests/guardrails.tftest.hcl` | offline unit tests with a **mocked provider** | asserts immutable tags, scan on push, validations |

`eks.tf` highlights:

- Public + private API endpoint (public is required so GitHub-hosted runners can reach it; **IAM auth is still mandatory**).
- `authentication_mode = "API"` → access only via IAM access entries.
- **Secrets envelope-encrypted** with a rotating customer-managed KMS key.
- All five control-plane **log types** to CloudWatch (30-day retention).
- Add-ons: `vpc-cni` (with **network policy enforcement on**, installed before nodes), `kube-proxy`, `coredns`, `metrics-server`.
- Node group: AL2023, **encrypted gp3** root disk, **IMDSv2 only with hop-limit 1** (pods can't steal node credentials),
  **no SSH** (SSM Session Manager policy instead), rolling updates one node at a time.

### The most important gotcha in this whole build

The module's default `enable_cluster_creator_admin_permissions = true` grants Kubernetes admin to *whoever runs
`terraform apply`*. But our pipeline **plans with the read-only role and applies with the deploy role**. The plan
(which is what gets applied) would have baked in the **plan role** as cluster admin, leaving the deploy role with
**no `kubectl` access** – the deploy would fail at the first `kubectl` command, after 15 minutes of cluster creation.

Fix: set it to `false` and explicitly add the **deploy role's ARN** (computed from the account id and
`deploy_role_name`) as an access entry with `AmazonEKSClusterAdminPolicy`. Same reasoning for `kms_key_administrators`.
Your own admin role can be added with the `EXTRA_ADMIN_ARNS` variable.

---

## 6. Kubernetes manifests – `k8s/`

| File | Contents |
|---|---|
| `namespace.yaml` | Namespace **`netflix`** with Pod Security Admission = `restricted`; `LimitRange` (defaults) and `ResourceQuota` (caps) |
| `backend.yaml` | ServiceAccount (token not mounted), Deployment (2 replicas), Service, **HPA** (2–4 @ 70 % CPU), **PodDisruptionBudget** |
| `frontend.yaml` | same pattern for nginx |
| `ingress.yaml` | two Ingresses in **one ALB group**: `/movies` (order 10) → backend, `/` (order 20) → frontend; separate health-check paths |
| `networkpolicy.yaml` | **default-deny ingress**; allow only the ALB's subnet range on port 8080 |
| `kustomization.yaml` | lists the files; CI rewrites the images with `kustomize edit set image` |

Per-pod hardening: `runAsNonRoot`, fixed UID, `seccomp: RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities: drop [ALL]`, `readOnlyRootFilesystem: true` (with a small `emptyDir` on `/tmp`), CPU/memory requests and limits,
startup/readiness/liveness probes, zone **topology spread**, and `maxUnavailable: 0` rolling updates.

Why `/movies` has the lower `group.order`: ALB evaluates rules in priority order; the catch-all `/` must come last.

---

## 7. GitHub Actions – `.github/`

| File | Purpose |
|---|---|
| `actions/tf-init/action.yml` | reusable step: `terraform init` with the S3 backend settings (DRY across 4 workflows) |
| `workflows/ci.yml` | PR + push + reusable. Jobs: Terraform (fmt, validate, TFLint, **terraform test**), Security (Trivy IaC + secrets), Kubernetes (kustomize → kubeconform), Images (build + Trivy vuln scan) |
| `workflows/plan.yml` | PR plan as a comment, **read-only role**, skipped for forks / before bootstrap |
| `workflows/deploy.yml` | manual. `preflight → ci → plan → (approval) → deploy` |
| `workflows/destroy.yml` | manual, must type `destroy`; cleans the ALB **before** `terraform destroy` |
| `dependabot.yml`, `CODEOWNERS` | automatic updates; review ownership of infra/pipeline changes |

Design points worth remembering:

- **Pinned by commit SHA** (with the version in a comment) – I resolved every SHA through the GitHub API. This defeats
  "moved tag" supply-chain attacks. Dependabot keeps them fresh.
- **Saved plan**: the `plan` job uploads `tfplan`; the `deploy` job applies **that exact file**. If reality changed in between, apply refuses.
- **Environment `production`** is both the human approval gate *and* the only identity the deploy role trusts.
- **Concurrency group** `aws-netflix-infra` (no cancel) – two applies can never run together.
- **Only from `main`**: deploy/destroy jobs have `if: github.ref == 'refs/heads/main'`.
- **Idempotent image push**: ECR tags are immutable, so the pipeline checks `describe-images` first and skips if the SHA tag exists (re-runs don't fail).
- **Wait loops** where AWS is eventually consistent: access-entry propagation, webhook readiness, ALB DNS, with retries and a diagnostics dump on failure.
- **No language setup actions** are used. The repo owner rule says to prefer `lmigtech/internal-actions/actions/setup-*`;
  those are private to your company org and a personal repo can't resolve them. Because builds run in Docker, none were needed.
  If you add one later, use the internal action.

### Teardown ordering (second most important gotcha)

The ALB and its security groups are created by the **controller**, not Terraform. Destroying the VPC first leaves them
orphaned and the VPC delete hangs. So `destroy.yml`: delete Ingresses (controller removes the ALB, finalizer waits) →
delete namespace → `helm uninstall` the controller → wait → `terraform destroy` with retries.

---

## 8. Validation performed (and what could not be validated)

| Check | Tool | Result |
|---|---|---|
| Terraform syntax/format | `terraform fmt -check`, `validate` (both stacks) | ✅ pass |
| Whole-stack plan logic without AWS | `terraform test` with mocked provider (3 runs) | ✅ pass |
| Terraform lint | TFLint | ✅ clean |
| IaC misconfiguration | Trivy `config` (HIGH/CRITICAL) | ✅ 0 findings (after fixing 2: state bucket needed a KMS CMK; frontend Dockerfile lacked explicit `USER`) |
| Workflow syntax | actionlint | ✅ clean |
| Manifests render | `kubectl kustomize` | ✅ 16 objects |
| Images | local Docker build + hardened run | ✅ both start and serve |

**Not possible from this machine – will first run in your pipeline:**

- A real `terraform apply` against AWS (no AWS credentials here). The IAM scoping of the deploy role is the most likely first-run
  failure; the Troubleshooting table in the README explains how to read an `AccessDenied` and the `deploy_role_admin_access` escape hatch.
- Trivy **vulnerability** scans and kubeconform schema checks: blocked locally by your network's TLS interception
  (certificate errors reaching `mirror.gcr.io` / `raw.githubusercontent.com`). They will run normally on GitHub's runners.
- The LBC → ALB → pod path and the NetworkPolicy allowing the ALB subnet range were designed from AWS documentation, not exercised live.

---

## 9. Things deliberately left out (and why)

HTTPS/custom domain (needs a domain you own), WAF, a private-only API endpoint (needs self-hosted runners),
multi-environment (dev/stage/prod), GitOps (Argo CD), Prometheus/Grafana, image signing (cosign), per-AZ NAT.
Each is listed with the interview-ready reasoning in [INTERVIEW-GUIDE.md](INTERVIEW-GUIDE.md#6-what-id-do-next-in-production).

---

## 10. Appendix – exact commands that were run during the build

```bash
# Look up versions
curl https://registry.terraform.io/v1/modules/terraform-aws-modules/eks/aws
helm search repo eks/aws-load-balancer-controller --versions

# Terraform validation (each stack)
terraform init -backend=false && terraform validate && terraform fmt -check -recursive
terraform test                                     # infra/ only
terraform providers lock -platform=linux_amd64 -platform=windows_amd64 \
                         -platform=darwin_arm64 -platform=darwin_amd64   # so CI (Linux) accepts the lock file

# Container checks
docker build -t netflix-backend:test backend
docker run --read-only --tmpfs /tmp --user 10001:10001 --cap-drop ALL --security-opt no-new-privileges -m 512m -p 18081:8080 netflix-backend:test

# Static analysis
docker run --rm -v "$PWD:/work" aquasec/trivy config --severity HIGH,CRITICAL /work
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint
docker run --rm -v "$PWD:/data" -w /data/infra ghcr.io/terraform-linters/tflint
kubectl kustomize k8s
```

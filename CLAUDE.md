# idp-platform

Single Internal Developer Platform with three cloud backends (AWS, Azure, GCP). One control plane, one API, per-cloud Compositions underneath. This is a portfolio project that also has to hold up in platform engineering interviews, so decisions should be defensible and written down as they are made.

## Goal

A developer runs a Backstage Scaffolder template, picks a cloud and a size, and gets a repo, a pipeline, cloud infrastructure, and a catalog entry with no manual steps. Cloud choice should not change the developer's experience.

### v1 scope

v1 (Phases 1 to 5, complete 2026-10-02) delivers cloud infrastructure and a catalog entry through a reviewed pull request, on all three clouds, with admission policy enforced. The cloud comes from the team, not a form field (ADR-0012). "A repo, a pipeline" from the Goal was deferred out of v1 and delivered by Phase 6 (ADR-0024, accepted 2026-10-02): two GitHub Apps with short-lived installation tokens, a dedicated organization for scaffolded repositories, public repositories so their CI costs no shared minutes, and keyless image publishing to ECR Public.

## Stack

- Control plane: K3s in a Lima VM on the MacBook (ADR-0010), configured by Ansible in bootstrap/k3s
- Portal: Backstage on that K3s cluster
- Provisioning: Crossplane v2 with namespaced XRs (ADR-0009), provider-aws, provider-azure, provider-gcp (Upbound providers), Composition Functions in Pipeline mode
- Bootstrap: Terraform, per cloud, run once
- Delivery: ArgoCD, app-of-apps, GitOps from this repo
- Policy: Kyverno
- Secrets: connection secrets composed as a Secret in the XR's namespace by the function pipeline (ADR-0009)
- Provider auth: K3s OIDC issuer federated to all three clouds, no long-lived keys (ADR-0001)

Terminology: this repo says claim for the developer-facing object. With Crossplane v2 that is a namespaced XR, not a legacy claim.

## Repo layout

```
bootstrap/        Terraform. aws/, azure/, gcp/, k3s/ (Argo, Crossplane, Backstage addons)
crossplane/
  providers/      ProviderConfig per cloud
  xrds/           cloud-agnostic APIs (xdatabase, xwebservice)
  compositions/   one file per XRD per cloud, labeled platform.jordandesigns.io/cloud=<aws|azure|gcp>
  functions/      function-patch-and-transform, function-go-templating
backstage/        catalog entities, scaffolder templates, app-config.yaml
argocd/           app-of-apps.yaml, projects/
policies/         Kyverno ValidatingPolicies (ADR-0023), tests/ per policy
claims/<team>/    claims written by the scaffolder, synced by Argo
```

API group: platform.jordandesigns.io. Claims select a Composition through compositionSelector.matchLabels on the cloud label.

## Phases

Work in this order. Do not start the next phase until the current one has a Ready claim and the verification checklist is complete.

1. AWS end to end: bootstrap/aws, bootstrap/k3s, xdatabase XRD, xdatabase-aws Composition, a Database claim that reaches Ready, then the Backstage template that writes that claim.
2. GCP: xdatabase-gcp Composition. This phase exists to find AWS assumptions that leaked into the XRD. Fix the XRD, not the Composition, when it does.
3. Azure: xdatabase-azure Composition.
4. xwebservice XRD and three Compositions, same order.
5. Kyverno policies (required tags, no public databases), FinOps tagging hooks.
6. Repo and pipeline scaffolding (ADR-0024, complete 2026-10-02): the service template creates a repository in idp-platform-apps with branch protection, CODEOWNERS, and CI that publishes a two-architecture image to ECR Public through OIDC, plus the claim and catalog entry by pull request; the deploy template moves the service to a built digest by pull request. Proven live on GCP, Azure, and AWS, including repeated image and size changes on AWS (ADR-0022).

## Abstraction rules

- The XRD exposes t-shirt sizes (small, medium, large). Each Composition maps them to cloud SKUs. Cloud SKU names never appear in the XRD.
- Add a platform-region map (us-east to us-east-1, eastus, us-east1) rather than accepting per-cloud region strings in the claim.
- Every status field that matters (endpoint, port) is patched back to the composite with ToCompositeFieldPath so consumers do not care which cloud produced it.
- Keep a DECISIONS.md at the repo root. Record every place the abstraction leaks (IAM models, networking, database knobs) and what was traded off. This feeds interview prep directly.

## Conventions

- AWS region: us-east-1. Terraform S3 backend bucket: tf-backend-jord-projs.
- Never use ACLs in S3 configuration.
- Deploy Terraform modules one at a time. After each module, produce a short verification checklist and confirm it before continuing.
- Prefer CLI-driven workflows over console actions.
- No inline comments inside terminal commands. Commands must be clean for direct copy and paste.
- No em dashes or spaced hyphens used as dashes in any generated prose or docs. Reword instead.
- Everything must be teardown-able. Every cloud footprint gets a destroy path and stays as small as the smallest managed tier allows. Use skipFinalSnapshot and equivalent settings on non-production databases.
- Do not create resources in a cloud before its bootstrap ProviderConfig is verified with a trivial managed resource (a bucket or resource group) that reaches Ready.

## Done criteria per phase

- kubectl get <claim> shows READY=True and SYNCED=True
- Connection secret exists in the claim namespace with the expected keys
- Argo application is Healthy and Synced
- Resource is visible in the cloud console or CLI with the required tags
- Destroying the claim removes the cloud resource and Argo returns to Synced
- DECISIONS.md updated

## Extending the platform

The engine can reach nearly the entire managed-resource surface of each cloud through the Upbound providers. The platform only offers what has an XRD and Compositions authored for it. This is a paved road, not a general-purpose Terraform replacement.

- Adding an infra type is additive: one cloud-agnostic XRD, one Composition per cloud, one Backstage template. Nothing already shipped changes.
- Author types in order of symmetry. Symmetric resources (object storage, queues, caches) are fast because the three clouds model them similarly. Asymmetric resources (IAM, networking, anything tied to identity) are slow because the abstraction leaks; spend the time in the XRD deciding what to expose versus hide, and record it in DECISIONS.md.
- Do not abstract everything. Offer a curated menu, not raw cloud APIs. A developer picks from what is paved.
- xcluster is a paved-road type, not the platform control plane. The control plane stays on K3s; xcluster provisions a hardened managed Kubernetes cluster (EKS first) that developers request and tear down per demo. Rationale, hardening baseline, and mandatory teardown order are in DECISIONS.md (ADR-0007). Networking for it follows the private-by-default, no-per-claim-NAT rule in ADR-0008.

Escape hatch. When a resource has no usable provider CRD, or is genuinely one-off, drop out of the paved road on purpose rather than forcing a bad abstraction:

- Use provider-terraform to run an existing Terraform module as a managed resource, wrapped in a Composition so the claim experience stays uniform.
- Any escape-hatch use gets a DECISIONS.md entry naming why the paved road did not fit and what the exit costs in maintenance.

## Compliance and controls

This platform is not SOC 2 certified and cannot be. SOC 2 is an audit of an organization over time by a licensed firm. What the platform does is implement and enforce the technical controls a SOC 2 audit tests, and make that mapping explicit. The story is control enforcement, not certification.

Compliance is a byproduct of the paved road. A developer cannot provision a non-compliant resource because the API and admission control will not allow it.

Control layers:

- Preventive: Kyverno ValidatingPolicies (ADR-0023; ClusterPolicy is deprecated in Kyverno 1.19) deny non-compliant claims and composed resources at admission. Each policy carries an annotation naming the control it satisfies, so the policy set is the control matrix. Policies also run in CI against rendered claims, not only at admission.
- Change management: GitOps. Every infra change is a reviewed, version-controlled PR synced by Argo. The scaffolder opens a PR, it never pushes to a synced path.
- Detective: cloud-native drift detection below Crossplane (AWS Config conformance packs, Azure Policy, GCP Security Command Center and Org Policy). Implement a slice for demos and destroy after; do not leave org-wide recording on.
- Evidence: Kyverno PolicyReports are machine-readable proof that no non-compliant resource was admitted.

Start from CIS Benchmarks and the cloud foundational security best-practice packs rather than a full framework. They are cheaper to stand up and overlap heavily with the SOC 2 Common Criteria below.

Control mapping. Annotate each Kyverno policy with `platform.jordandesigns.io/control` listing the IDs it satisfies.

| Kyverno policy | SOC 2 (Common Criteria) | CIS control | What it enforces |
|---|---|---|---|
| require-tags | CC6.1, CC3.2 | CIS 1.1 (asset inventory) | Owner, cost-center, environment on every claim; claims only in team-* namespaces (Team tag) |
| restrict-cost-centers | CC3.2 | FinOps | A claim bills only to a cost center finance has opened |
| require-cost-allocation-tags | CC3.2 | FinOps | Every billable composed resource carries the cost center (FinOps tagging hook) |
| deny-public-database | CC6.6, CC6.1 | CIS 5.2 (limit network exposure) | Composed RDS, Cloud SQL, and Flexible Server have public access explicitly off |
| require-encryption-at-rest | CC6.7 | CIS 3.11 (encrypt at rest) | RDS storageEncrypted (GCP and Azure cannot turn it off) |
| require-tls-in-transit | CC6.7 | CIS 3.10 (encrypt in transit) | Cloud SQL refuses unencrypted connections; container apps refuse plain HTTP |
| restrict-sizes | CC8.1, CC3.4 | CIS 2.x (config hardening) | Only small, medium, large; no Composition chosen except by the cloud label |
| require-review-source | CC8.1 | CIS 4.x (change control) | Claims are written only by Argo CD (or Crossplane); server dry runs allowed |
| least-privilege-connsecret | CC6.1, CC6.3 | CIS 1.x (access management) | RoleBindings in team namespaces bind only that namespace's service accounts, never cluster-admin |
| deny-internal-webservice-aws | CC6.6 | CIS 5.2 (limit network exposure) | visibility internal on AWS refused while the internal ALB is off (ADR-0022) |
| restrict-pod-security (deferred with xcluster) | CC7.1 | CIS EKS 4.2 (pod security) | Pod Security Standards restricted on xcluster workloads: no privileged, no hostPath, drop capabilities, read-only root fs, runAsNonRoot |
| require-private-cluster-endpoint (deferred with xcluster) | CC6.6 | CIS EKS 5.4 (private endpoint) | xcluster API server private or CIDR-restricted, nodes without public IPs |

Done criteria for the compliance phase:

- Every Kyverno policy carries a control annotation and a CI test that proves it denies a violating claim.
- A PolicyReport shows pass or fail per control across live claims.
- DECISIONS.md records the auth model, secret handling, and the compliance model (preventive versus detective, and what is deferred).

## Out of scope

Multi-cluster, multi-region failover, production hardening, cost optimization beyond tagging and small tiers. SOC 2 certification itself, org-level audit process, and full framework coverage beyond the mapped controls above.

# DECISIONS

Architecture decision records for idp-platform. One entry per decision. Newest at the top. Record every place the abstraction leaks and what was traded off. This feeds interview prep directly.

Status values: Proposed (design intent, not yet validated in a cloud), Accepted (validated or committed), Superseded (replaced by a later ADR).

Format: Context, Decision, Consequences.

---

## ADR-0017: RDS external names are assigned by AWS, so re-adoption is a lookup, not automatic

Status: Accepted. Amends ADR-0010.

Context. ADR-0010 says every Composition sets a deterministic external name, so a rebuilt control plane re-adopts cloud resources from the XRs in git. In provider-upjet-aws v2.8.1 the RDS Instance uses IdentifierFromProvider: its external name is the AWS DbiResourceId (db-XXXX), assigned at creation, and the human identifier is an ordinary spec field. The first Phase 1 attempt set the crossplane.io/external-name annotation to the identifier; the provider ignored it as a name, left identifier empty, and Terraform generated terraform-<random>. The IAM prefix scope from ADR-0014 denied CreateDBInstance, so nothing was created. That is the permissions design working as a guardrail, and it is the reason the identifier scope stays.

Decision. The Composition sets spec.forProvider.identifier to idp-<namespace>-<name> and leaves the external name to the provider. Which external-name strategy a resource uses is checked in the provider's config/externalname.go before its Composition is written, and each Composition's comment says which it is.

Consequences. The identifier is still deterministic, so a rebuilt control plane cannot create a duplicate: a fresh MR fails with DBInstanceAlreadyExists instead of orphaning a second billed database. Re-adoption becomes a manual lookup: read the DbiResourceId with aws rds describe-db-instances --db-instance-identifier idp-<namespace>-<name>, and set it as the crossplane.io/external-name annotation on the new Instance MR. This procedure is written down but has not been exercised against a rebuilt control plane. Resources whose provider uses the name as the external name (for example the S3 Bucket in Phase 0) keep the automatic re-adoption ADR-0010 describes. This is a per-resource leak of the provider implementation into the platform's recovery story, and every new Composition must record which kind it is.

---

## ADR-0016: The connection Secret is a platform contract, readiness waits for it

Status: Accepted for AWS (validated live 2026-09-30)

Context. ADR-0009 composes the connection Secret in the function pipeline because namespaced XRs have no writeConnectionSecretToRef. Each cloud's provider publishes different connection keys (upjet RDS publishes its own names; Azure and GCP will differ again), so passing a provider's Secret through would leak the cloud into every consumer. A second problem surfaced in crossplane render: function-auto-ready marks the XR Ready once every desired composed resource is ready, so if the Secret is only composed after the password appears, the XR goes Ready before a usable Secret exists.

Decision. Every xdatabase Composition composes a Secret named <xr-name>-conn in the XR namespace with exactly these keys: host, port, username, password, dbname, sslmode. The XR's status.connectionSecret names it. The Secret is always composed and carries the go-templating ready annotation, set True only when host, port, and password are all present, so XR Ready implies a complete Secret. On AWS the provider also writes two internal Secrets in the same namespace: <name>-master (autoGeneratePassword output) and <name>-rds (the MR's own connection details, which is how the password reaches the pipeline).

Consequences. Consumers and the Backstage template depend on one Secret shape regardless of cloud. Three Secrets exist per AWS Database, two of them internal, all namespace scoped (least-privilege-connsecret). The password is still plaintext in Kubernetes Secrets; the External Secrets path in ADR-0002 remains deferred. crossplane render cannot mock composed connection details, so the password branch is only proven live. Live proof, 2026-09-30: Database team-demo/db-demo reached READY and SYNCED in about five minutes; db-demo-conn held exactly the six keys, its password matched the provider's db-demo-master Secret, and the endpoint resolved to a private 10.60.0.0/16 address. AWS showed db.t4g.micro, Postgres 17.9, 20 GiB gp3, not public, encrypted, single AZ, no backups, the shared subnet group and security group, and all required tags.

---

## ADR-0015: XR names become cloud identifiers, so the XRD enforces the strictest naming rule

Status: Accepted

Context. ADR-0010 requires deterministic external names so a rebuilt control plane re-adopts cloud resources. On AWS the RDS identifier is idp-<namespace>-<name>, and RDS allows 1 to 63 characters, lowercase letters, digits, and hyphens, starting with a letter, with no double hyphens and no trailing hyphen. Kubernetes names allow dots, and up to 253 characters. Azure Postgres Flexible Server names must be globally unique DNS labels, and GCP Cloud SQL instance names cannot be reused for about a week after deletion. The cloud's naming rules leak into the platform API whether or not the XRD admits it.

Decision. The XRD carries a root CEL rule: a Database name is 1 to 30 lowercase letters, digits, or single hyphens, starting with a letter and not ending with a hyphen. With the idp- prefix, this leaves 28 characters for the namespace inside the 63 character RDS limit. Team namespaces follow the same rule by convention until a Kyverno policy enforces it in Phase 5.

Consequences. Developers see a naming error at admission instead of a cloud API error minutes later. The rule is stricter than any single cloud needs, which is the price of one API. Two leaks remain for later phases: Azure global uniqueness will need a suffix that is still deterministic (for example a hash of namespace and name), and GCP name reuse means deleting and recreating a Database with the same name can fail for a week. Both get recorded against this ADR when their phases hit them.

---

## ADR-0014: Database network attachment is shared bootstrap, not per claim

Status: Accepted for AWS (validated 2026-09-30)

Context. ADR-0008 puts networking in bootstrap and says each Composition implements the intent "reachable only from the platform network" in its own cloud primitive. On AWS that primitive is a security group plus an RDS subnet group. The obvious design gives every Database claim its own security group. That rule would be identical on every claim (tcp/5432 from the VPC CIDR), so per-claim groups add no isolation, while they require provider-aws-ec2 on the control plane (roughly 300 MiB on a 4 GiB VM, ADR-0010) and ec2 write permissions on the provider role.

Decision. bootstrap/aws/network creates one security group per engine (idp-platform-us-east-postgres: tcp/5432 from the VPC CIDR, no egress) and one RDS subnet group (idp-platform-us-east) across the private subnets. The xdatabase-aws Composition attaches every instance to both, reading their IDs from the platform-regions EnvironmentConfig, so the XRD never sees them. The provider role gets RDS instance lifecycle on the idp- identifier prefix only, with creation gated on aws:RequestTag/Project and changes gated on aws:ResourceTag/Project, and no ec2 write access at all.

Consequences. Smaller control plane and a smaller blast radius for the provider role. The trade is no network isolation between two databases inside the platform VPC: any workload in the VPC can reach any platform Postgres port, and authentication is the only barrier between tenants. If a tenant needs isolation from other tenants, the fix is per-claim security groups sourced from that tenant's workload group, which reintroduces provider-aws-ec2 and scoped ec2 permissions. Two IAM leaks surfaced while scoping the role: CreateDBInstance and ModifyDBInstance authorize against the subnet group, parameter group, and option group ARNs as well as the instance, so those ARNs are pinned in the policy and a new Postgres major version is a reviewed IAM diff; and the RDS service-linked role must already exist, because the permissions boundary denies all IAM. A third leak appeared on the first live reconcile: before it knows an instance's resource ID the provider looks it up by filter, so AWS evaluates DescribeDBInstances against db:* rather than the prefix. The policy grants that single read-only action on arn:aws:rds:us-east-1:<account>:db:*, not on *, and every write stays prefix and tag scoped. Validated with iam simulate-principal-policy: tagged create on the prefix allowed; untagged create, other prefixes, untagged deletes, other regions, other subnet groups, ec2 writes, IAM, and Aurora clusters denied.

---

## ADR-0013: Providers come from crossplane-contrib, not the Upbound registry

Status: Accepted

Context. The Upbound registry (xpkg.upbound.io) now requires authentication to pull the official provider packages. Pulling them would put an Upbound account token on the control plane as a pull secret, which is a long-lived credential ADR-0001 exists to avoid, and ties the platform to a vendor account.

Decision. Install the crossplane-contrib builds of provider-upjet-aws, provider-upjet-azure, and provider-upjet-gcp from xpkg.crossplane.io. They are built from the same upjet source and expose the same API groups (aws.upbound.io, aws.m.upbound.io, and so on), so Compositions do not change. Pin exact versions (AWS starts at v2.8.1) and install the family provider explicitly with skipDependencyResolution, so no package is pulled that was not reviewed.

Consequences. No registry credential on the cluster and no vendor account dependency. Version cadence follows the community releases rather than Upbound's. If a feature ships only in Upbound's builds, record it here before switching.

---

## ADR-0012: Cloud is assigned by team policy, not picked freely per resource

Status: Proposed

Context. The goal says a developer picks a cloud. In real organizations developers rarely choose a cloud per database. The cloud follows from an acquisition, a data residency rule, a customer contract, or where the team's other workloads already run. Presenting cloud choice as a free per-request pick invites the interview question of why anyone would want it, and has no good answer.

Decision. Each team has a default cloud recorded on its Backstage group entity. The scaffolder template pre-fills the cloud from that default and hides the field unless the team is allowed to override it. The XR still carries the cloud as a label that selects the Composition, so the API does not change. Kyverno can later enforce that a namespace only creates XRs for its team's allowed clouds.

Consequences. The developer experience stays identical across clouds, which is the real promise. The multi-cloud value is framed as one platform serving teams that live on different clouds, which matches how platform teams actually operate. Adds a small amount of catalog metadata and one template conditional.

---

## ADR-0011: Workload identity federation leaks per cloud, and the issuer lives in AWS

Status: Accepted for AWS and Azure (validated 2026-09-30). GCP pending its phase.

Context. ADR-0001 federates the K3s service account issuer to all three clouds. Each cloud matches the Kubernetes identity differently. AWS IAM trust policies accept StringLike on the sub claim, so one role can trust every provider-aws service account with a wildcard. GCP Workload Identity Federation evaluates a CEL attribute condition, so a prefix match works. Azure federated identity credentials on a user-assigned managed identity accept only an exact subject, with a limit of 20 credentials per identity. Crossplane generates provider service account names that include the package revision, so exact matching breaks on every provider upgrade.

Decision. Give every provider a fixed service account name through a DeploymentRuntimeConfig serviceAccountTemplate, on all three clouds rather than only Azure, so the identity model is uniform. Keep the AWS and GCP trusts as tight as the Azure one where practical. The issuer's discovery document and JWKS are hosted on a private S3 bucket behind CloudFront with Origin Access Control (bootstrap/aws/oidc-issuer).

Consequences. Azure and GCP authentication depend on the AWS-hosted issuer being reachable. If CloudFront or the bucket is unavailable, new tokens fail to validate on every cloud. Accepted because the issuer is two static documents on a highly available CDN, and moving it (another CDN, a custom domain) only requires changing the issuer URL and republishing. Rotating the K3s service account signing key requires republishing the JWKS; caching is disabled on the distribution so the new key is served immediately.

A second leak surfaced during validation: in provider-azure v2, ResourceGroup is reconciled by the family provider itself, while in provider-aws every resource type lives in a sub-provider. So which pod carries the cloud identity differs per cloud, and the Azure family provider needs the token mount and a federated credential while the AWS family provider needs neither. The list of provider service accounts per cloud lives in each crossplane-auth module and must track which pods reconcile resources.

---

## ADR-0010: Control plane runs in a Lima VM on the MacBook

Status: Accepted (validated 2026-09-30). Amends ADR-0007.

Context. ADR-0007 assumes an always-on K3s control plane. No always-on host is available yet, and a cloud VM would add standing cost and put the platform brain inside one of the clouds it manages. The available host is an Apple M1 MacBook with 8 GB of RAM and limited free disk, which sleeps.

Decision. Run K3s in a Lima VM (Apple Virtualization framework, arm64 Ubuntu 24.04, 4 vCPU, 4 GiB, 20 GiB sparse disk) defined in bootstrap/k3s/lima and configured by the Ansible playbook in bootstrap/k3s/ansible. The VM has no host mounts so provider pods cannot see local cloud credentials, and only the Kubernetes API is forwarded to the Mac, bound to localhost. Install components by phase rather than all at once to fit in 4 GiB. Rules that follow:

- Never stop the VM or close the laptop while cloud resources exist. The Makefile refuses to stop or delete the VM while any Crossplane managed resource exists, and per-cloud budget alerts are the backstop.
- Every Composition sets deterministic external names on its managed resources, so a rebuilt control plane re-adopts existing cloud resources from the XRs in git instead of orphaning them. Amended by ADR-0017: where the provider assigns the external name (RDS), the Composition sets a deterministic identifier instead and re-adoption is a lookup.
- The same playbook targets an always-on host later. Moving hosts means copying the K3s service account signing key, or republishing the JWKS, and the cloud trusts from ADR-0001 keep working.

Consequences. Zero standing cost and fast iteration. Reconciliation pauses whenever the laptop sleeps, so drift correction and deletion only happen while it is awake. Backstage is not linkable between demos, which ADR-0007 listed as a benefit; that returns when the control plane moves to an always-on host. Memory is the binding constraint and will shape how many providers run concurrently. Measured at the end of Phase 0: K3s, Crossplane, provider-family-aws, provider-aws-s3, and provider-family-azure use about 2.3 GiB of the 4 GiB VM with one active managed resource type per cloud. The stop guard was tested by creating a Bucket and running make vm-stop, which refused.

---

## ADR-0009: Crossplane v2 with namespaced composite resources

Status: Accepted

Context. The original design used Crossplane v1 claims and writeConnectionSecretToRef. Crossplane v2 makes namespaced composite resources (XRs) the developer-facing API and keeps claims only for legacy cluster-scoped XRDs. Namespaced XRs do not support writeConnectionSecretToRef. Upbound providers publish namespaced managed resources for v2.

Decision. Use Crossplane v2. XRDs are namespaced, and developers create XRs directly in their team namespace. Where this repo says claim, it means a namespaced XR. Connection details are produced by composing a Kubernetes Secret in the function pipeline, into the XR's own namespace. Only the managed resource types a phase needs are activated, which keeps CRD count and API server memory down on the small control plane (ADR-0010).

Consequences. Follows the supported model instead of a legacy path. Namespace becomes the tenancy and RBAC boundary for both the XR and its Secret, which strengthens the least-privilege-connsecret control. ADR-0002's mechanism changes from writeConnectionSecretToRef to a composed Secret; its External Secrets deferral stands. Kyverno policies match the XR kinds instead of claim kinds. Operational note from Phase 1: Crossplane v2 keeps a provider's deployment at zero replicas until at least one of its ManagedResourceDefinitions is active, so the MRAP must be applied before waiting for a new provider's pod.

---

## ADR-0008: Networking is a bootstrap concern, private by default, no per-claim NAT

Status: Accepted for AWS (validated 2026-09-30). Proposed for Azure and GCP until their phases.

Context. Networking is the largest leaky abstraction across the three clouds (AWS VPC and security groups, Azure VNet and NSGs, GCP VPC network and firewall rules are all modeled differently) and it is also a primary security and cost surface. Two failure modes to avoid: leaking cloud network primitives into the cloud-agnostic API, and letting each claim create its own VPC and NAT gateway, which is both sprawl and the main cost landmine from ADR-0004.

Decision. Networking lives in bootstrap, not in claims. Each cloud's bootstrap provisions one shared, private-by-default network (VPC, VNet, VPC network) with private subnets across the zones the platform-region map covers. Claims attach to it through the region map. The XRD never exposes CIDRs, subnet IDs, security groups, or any network primitive. The claim expresses intent only, for example reachable only from the platform network, and each Composition implements that intent in the cloud's own primitive.

Posture:

- Private by default. Databases and nodes get no public IPs. Cluster API server endpoints are private (ties ADR-0007). Managed resources are reachable only from within the platform network.
- Egress without per-claim NAT. Use private connectivity to cloud services (AWS VPC endpoints, Azure Private Link, GCP Private Service Connect) so managed resources reach cloud APIs without a NAT gateway. If a workload genuinely needs internet egress, use one shared NAT per cloud created in bootstrap and destroyed with it, never one per claim. (Resolves the ADR-0004 cost tension.)
- Default-deny firewalling. Security groups, NSGs, and firewall rules start default-deny and open only the specific ports a resource needs, source-restricted to the platform network. (CC6.6, CIS limit-network-exposure)
- Verification without public exposure. The database phase done-criteria (READY=True, connection secret exists) does not require the K3s control plane to reach a private database, so no public path is opened for verification. A true end-to-end connect test runs from inside the cloud network (a throwaway job in the provisioned xcluster or a bastion), not from K3s over the internet.

Consequences. Claims stay cheap and cloud-agnostic, no VPC or NAT sprawl, and the private-by-default posture maps directly to the compliance controls. The cost of shared bootstrap networking is that it is created and destroyed as a unit per cloud, so a demo cycle stands up the network with the first claim and tears it down after the last. The security-group versus NSG versus firewall-rule difference is a known abstraction leak: the XRD carries intent, each Composition carries the implementation, and each new leak gets its own note here. Marked Proposed until validated in the AWS phase, then updated to Accepted with the concrete endpoint and egress mechanism per cloud.

AWS, validated 2026-09-30 (bootstrap/aws/network): VPC 10.60.0.0/16 with two private /20 subnets in us-east-1a and us-east-1b, no internet gateway, no NAT gateway, and a route table holding only the local route and the S3 gateway endpoint. The default security group is adopted with zero rules. Egress mechanism: gateway endpoints only; RDS needs no endpoint because the provider calls the RDS API from K3s, not from inside the VPC. VPC flow logs (ALL traffic) go to CloudWatch with 7 day retention and the managed key, which avoids a standing CMK charge. Standing cost is $0 per month. Database attachment is shared bootstrap per ADR-0014.

---

## ADR-0007: Control plane stays on K3s; EKS is a provisioned type, not the platform brain

Status: Accepted. Amended by ADR-0010 (K3s host is a Lima VM on the laptop, not always on).

Context. EKS was considered as the control plane that runs Backstage, Argo, and Crossplane. It is the most production-like option but has a standing control-plane cost of roughly $73/month per cluster that cannot be paused. The deeper problem is that the control plane is the platform brain: Crossplane's record of every cloud resource it provisioned lives inside the cluster as Kubernetes objects. Destroying that cluster while claims are live orphans billed cloud resources with no controller left to clean them up. It also forces a full Phase 0 re-bootstrap on every demo and leaves nothing running between demos.

Decision. Hybrid. K3s stays the always-on control plane at near-zero marginal cost, so the platform brain never dies, bootstrap is one-time, and there is no orphaning risk. EKS becomes a paved-road offering: a hardened xcluster type developers request and tear down per demo, following the additive-type pattern in ADR-0006. This gives a full production-grade EKS build and story without making the platform depend on it.

EKS hardening baseline for the xcluster Composition, mapped to the controls in the compliance section:

- Access via EKS access entries, not the aws-auth ConfigMap. Pods get AWS permissions via EKS Pod Identity or IRSA, never the node role. IMDSv2 enforced, hop limit 1. (CC6.1, CC6.3)
- Private API server endpoint, or public restricted to a CIDR allowlist. Nodes in private subnets, no public IPs. Default-deny NetworkPolicies. (CC6.6)
- Secrets envelope-encrypted with a customer-managed KMS key. (CC6.7)
- Bottlerocket nodes or Fargate; managed add-ons kept current; automated AMI patching. (CIS config hardening)
- Pod Security Standards at restricted, enforced by Kyverno: no privileged, no hostPath, drop capabilities, read-only root fs, runAsNonRoot. Image scanning and signature verification in CI. (CC7.1)
- All five control-plane log types to CloudWatch; GuardDuty EKS Protection on; kube-bench against the CIS EKS Benchmark. (CC7.2, evidence)

Mandatory teardown order for the xcluster (out-of-band AWS resources are created by Kubernetes, not Terraform, so order matters):

1. Delete all workload claims on the cluster and wait for Crossplane to confirm the underlying cloud resources are gone.
2. Delete Services of type LoadBalancer and confirm their ELBs and ENIs are removed.
3. Destroy the cluster.
4. Destroy the VPC and networking last.

Consequences. Platform survives teardown, no re-bootstrap tax, no orphaning risk, and Backstage stays live and linkable between demos. EKS spend accrues only while an xcluster is up and is destroyed with it. The platform does not run on EKS, which is a deliberate trade of maximum production fidelity for teardown safety and cost. Supersedes the option of running the control plane on EKS.

---

## ADR-0006: Escape hatch for resources the paved road does not fit

Status: Accepted

Context. The Upbound providers reach nearly the whole managed-resource surface of each cloud, but the platform only offers what has an XRD and Compositions. Some resources are one-off, or have no usable provider CRD, or would force a bad three-cloud abstraction. Trying to pave everything produces leaky XRDs that are worse than no abstraction.

Decision. Offer a curated paved road plus a documented exit. When a resource does not fit, drop out on purpose using provider-terraform to run an existing Terraform module as a managed resource, wrapped in a Composition so the claim experience stays uniform. Every escape-hatch use gets its own ADR naming why the paved road did not fit and what the exit costs in maintenance.

Consequences. Keeps the paved road opinionated and small. Preserves a uniform claim experience even for long-tail resources. Adds a second provisioning path to maintain, which is acceptable because it is bounded and documented. Interview line: a mature platform offers a paved road and a documented exit, not one or the other.

---

## ADR-0005: Compliance model is control enforcement, not certification

Status: Accepted

Context. The project should tell a compliance story without overclaiming. SOC 2 is an organizational audit over time by a licensed firm and cannot be a property of a portfolio platform. Claiming certification is an instant credibility loss.

Decision. Implement and enforce the technical controls a SOC 2 audit tests, and make the mapping explicit. Preventive controls are Kyverno ClusterPolicies that deny non-compliant claims at admission, each annotated with `platform.jordandesigns.io/control` naming the SOC 2 Common Criteria and CIS IDs it satisfies. Change-management control is GitOps: every change is a reviewed PR synced by Argo, the scaffolder opens a PR and never pushes to a synced path. Detective controls are cloud-native (AWS Config, Azure Policy, GCP Security Command Center), implemented as a slice for demos and destroyed after. Evidence is Kyverno PolicyReports. Start from CIS Benchmarks rather than a full framework.

Consequences. Compliance becomes a byproduct of the paved road: a developer cannot provision a non-compliant resource because the API will not allow it. The policy set doubles as the control matrix. Certification, org-level audit process, and full-framework coverage stay out of scope. Detective controls carry small per-evaluation cloud charges, so they run deploy-demo-destroy like everything else.

---

## ADR-0004: Cost containment, avoid always-on billed resources

Status: Proposed

Context. The control plane runs on the existing K3s cluster at near zero marginal cost. All cloud spend comes from resources a claim provisions. Some resources bill hourly whether or not they are used, and can quietly dwarf the databases: NAT gateways (~$0.045/hr plus data), cloud load balancers (~$16 to $25/mo each), zone-redundant HA (roughly doubles compute), and provisioned IOPS.

Decision. Compositions default to the smallest managed tier, skipFinalSnapshot and equivalents on, HA off, baseline IOPS. Databases are reachable without a per-claim NAT gateway; reuse existing networking or private connectivity that does not require one. The xwebservice load balancer is treated as the main cost line and destroyed with the claim. A small budget alert per cloud catches a forgotten always-on resource.

Consequences. A single deploy-verify-destroy cycle across all three databases stays well under one dollar. Leaving one database up a full month is roughly fifteen dollars. The design forgoes production availability features by choice, which matches the out-of-scope list. Revisit before any resource is intended to stay up.

---

## ADR-0003: Platform region map instead of per-cloud region strings

Status: Accepted

Context. Each cloud names regions differently (us-east-1, eastus, us-east1). Accepting raw per-cloud region strings in the claim would leak cloud specifics into the cloud-agnostic API and break the promise that cloud choice does not change the developer experience.

Decision. The XRD exposes platform regions (for example us-east). A single platform-region map translates to the per-cloud region in each Composition. The map lives in one place via an EnvironmentConfig rather than being duplicated inside every Composition. Cloud SKU names and cloud region strings never appear in the XRD.

Consequences. Developers pick a platform region and get the right cloud region underneath. The map is the one place to maintain region coverage. Adds an EnvironmentConfig dependency to the bootstrap. Regions that do not exist in every cloud must be handled explicitly in the map, which is itself a leak to record when it happens.

Implementation, 2026-09-30: the map is the cluster-scoped EnvironmentConfig platform-regions (crossplane/environment/platform-regions.yaml), loaded into each Composition pipeline by function-environment-configs. Each platform region entry carries the cloud region plus that cloud's shared network attachment from bootstrap (ADR-0014), so bootstrap outputs reach Compositions without touching the XRD. The XRD's region field is an enum of platform regions and is immutable after creation; adding a region is one enum value in the XRD plus one map entry. A known pending leak: this Azure subscription has previously been restricted from Postgres Flexible Server in eastus, so us-east may have to map to a different Azure region than its name suggests. Phase 3 confirms or resolves it here.

---

## ADR-0002: Connection secret handling and the External Secrets deferral

Status: Proposed. Mechanism amended by ADR-0009: the Secret is composed in the function pipeline, not written via writeConnectionSecretToRef.

Context. Crossplane writes connection details to the claim namespace via writeConnectionSecretToRef. That means plaintext database credentials sit in a Kubernetes Secret. Acceptable for a demo, weak for a production-mimicking story, and a predictable interview probe.

Decision. For the initial phases, keep writeConnectionSecretToRef with RBAC scoped so only the claim namespace can read the secret, and a Kyverno policy keeping connection secrets in-namespace. Record External Secrets Operator as the intended production path: sync connection details into each cloud's secret manager and back, so no long-lived plaintext credential is the source of truth. Implement or explicitly defer ESO, and note which in this ADR when decided.

Consequences. Fast to ship, honest about the tradeoff. The gap between the demo path and the production path is written down rather than hidden, which is the stronger interview position. If ESO is deferred past the compliance phase, revisit against ADR-0005 (CC6.1 access control).

---

## ADR-0001: Provider authentication and bootstrap secret storage

Status: Accepted for AWS and Azure (validated 2026-09-30). Proposed for GCP.

Context. The K3s cluster lives outside all three clouds, so Crossplane needs a way to authenticate to each of them. Long-lived plaintext cloud keys in a Secret, or worse in git, is the single biggest credibility gap for a platform that claims to mimic production. The first draft preferred AWS IAM Roles Anywhere, Azure federated service-principal credentials, and GCP Workload Identity Federation. Roles Anywhere turned out to be a poor fit: the Upbound provider-aws ProviderConfig has no Roles Anywhere credential source, so it would need aws_signing_helper in a custom provider image or sidecar, plus a private CA whose key still has to be stored somewhere.

Decision. Make K3s its own OIDC issuer and federate that one issuer to all three clouds. K3s signs projected service account tokens with a public issuer URL (a private S3 bucket behind CloudFront, ADR-0011), and the discovery document and JWKS are published there. Each cloud trusts the issuer:

- AWS: IAM OIDC provider plus a role assumed with AssumeRoleWithWebIdentity. ProviderConfig source IRSA, with the projected token and role ARN injected by a DeploymentRuntimeConfig.
- Azure: user-assigned managed identity with federated identity credentials. ProviderConfig source OIDCTokenFile.
- GCP: Workload Identity Federation pool and OIDC provider, impersonating a service account. The external_account credential config holds no key material. The project enforces iam.disableServiceAccountKeyCreation.

No provider credential is a secret, so SOPS or Sealed Secrets is not needed for provider auth; it is still required later for Argo repository credentials and the Backstage GitHub token. Provider IAM is least privilege: Phase 0 grants only what the verification resources need, and each phase adds exactly what its Compositions manage, as a reviewed diff. AWS permissions sit under a boundary that denies IAM changes and regions other than us-east-1. No cloud resource is created before its ProviderConfig is verified with a trivial managed resource that reaches Ready.

Consequences. No long-lived cloud credential exists anywhere in the platform runtime, and one issuer gives a uniform identity story across three clouds. The human bootstrap path (Terraform run from the laptop) still uses a local IAM user, which is out of scope for the platform runtime and recorded here so it is not overlooked. Rotating the K3s signing key means republishing the JWKS. Validation, 2026-09-30:

- AWS: provider-aws-s3 assumed idp-crossplane-provider-aws through AssumeRoleWithWebIdentity (CloudTrail userName system:serviceaccount:crossplane-system:provider-aws-s3). A namespaced Bucket reached SYNCED and READY and was deleted cleanly. IAM simulation allows CreateBucket only on the verification prefix and denies other buckets, RDS, and IAM. The ProviderConfig uses source WebIdentity with a Filesystem token rather than IRSA, so the role ARN is explicit in the ProviderConfig instead of hidden in pod environment variables.
- Azure: provider-family-azure authenticated with source OIDCTokenFile against a user-assigned managed identity. A namespaced ResourceGroup reached SYNCED and READY with the required tags and was deleted cleanly.
- The cluster holds no cloud credential Secret, and no provider pod has an access key or client secret in its environment.

Accepted for AWS and Azure. GCP stays Proposed until its phase validates Workload Identity Federation.

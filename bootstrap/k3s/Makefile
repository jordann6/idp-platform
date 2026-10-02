VM            := idp-k3s
KUBECONFIG    := $(HOME)/.kube/idp-k3s.yaml
KCTL          := kubectl --kubeconfig $(KUBECONFIG) --context idp-k3s
ISSUER_TF     := ../aws/oidc-issuer
AUTH_TF       := ../aws/crossplane-auth
GCP_AUTH_TF   := ../gcp/crossplane-auth
AZURE_AUTH_TF := ../azure/crossplane-auth
DISCOVERY_DIR := $(ISSUER_TF)/discovery

# Provider Healthy can read True before the runtime pod exists, so also wait
# for the provider pod itself to be Ready. Crossplane v2 keeps a provider's
# deployment at zero replicas until one of its MRDs is active, so the MRAP
# must be applied before this wait or it never returns.
define wait_provider_pod
	until $(KCTL) -n crossplane-system get pod -l pkg.crossplane.io/provider=$(1) -o name | grep -q .; do sleep 2; done
	$(KCTL) -n crossplane-system wait pod -l pkg.crossplane.io/provider=$(1) --for=condition=Ready --timeout=600s
endef

# Removing a family provider marks its ClusterProviderConfig for deletion,
# held by the in-use finalizer until the provider returns and clears it. On a
# reinstall, applying the config while it is still terminating is a no-op and
# the provider then deletes it, so wait for the old object to go first.
define wait_config_settled
	@if $(KCTL) get $(1) -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null | grep -q .; then echo "waiting for terminating $(1)"; $(KCTL) wait --for=delete $(1) --timeout=300s; fi
endef

.PHONY: vm-up vm-stop vm-destroy k3s k3s-check verify discovery-docs guard-no-managed

vm-up:
	if limactl list -q | grep -qx $(VM); then limactl start $(VM); else limactl start --name=$(VM) --tty=false lima/idp-k3s.yaml; fi

vm-stop: guard-no-managed
	limactl stop $(VM)

vm-destroy: guard-no-managed
	limactl delete --force $(VM)

k3s:
	cd ansible && ansible-playbook k3s.yml -e issuer_url=$$(terraform -chdir=../$(ISSUER_TF) output -raw issuer_url)

k3s-check:
	cd ansible && ansible-playbook k3s.yml --check --diff -e issuer_url=$$(terraform -chdir=../$(ISSUER_TF) output -raw issuer_url)

verify:
	$(KCTL) get nodes -o wide
	$(KCTL) get --raw /.well-known/openid-configuration
	@echo

discovery-docs:
	$(KCTL) get --raw /.well-known/openid-configuration > $(DISCOVERY_DIR)/openid-configuration.json
	$(KCTL) get --raw /openid/v1/jwks > $(DISCOVERY_DIR)/jwks.json
	@grep -q "$$(terraform -chdir=$(ISSUER_TF) output -raw issuer_url)" $(DISCOVERY_DIR)/openid-configuration.json || (echo "issuer in discovery doc does not match Terraform output" && exit 1)
	@echo "Wrote discovery docs to $(DISCOVERY_DIR)"

# ADR-0010: stopping or deleting the VM with live managed resources leaves
# billed cloud resources with no controller reconciling them.
guard-no-managed:
	@$(KCTL) get --raw /readyz >/dev/null 2>&1 || (echo "Refusing: cluster unreachable, so live managed resources cannot be ruled out. Run make vm-up first." && exit 1)
	@out=$$($(KCTL) get managed -A -o name) || { echo "Refusing: cannot list managed resources, so live ones cannot be ruled out."; exit 1; }; \
	count=$$(printf '%s' "$$out" | grep -c . || true); \
	if [ "$$count" != "0" ]; then echo "Refusing: $$count Crossplane managed resources still exist. Delete XRs first."; exit 1; fi

CROSSPLANE_VERSION := 2.4.2

.PHONY: crossplane-install aws-provider aws-verify aws-verify-delete

crossplane-install:
	helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update
	helm upgrade --install crossplane crossplane-stable/crossplane --version $(CROSSPLANE_VERSION) --namespace crossplane-system --create-namespace --kubeconfig $(KUBECONFIG) --kube-context idp-k3s --values crossplane/values.yaml --wait

aws-provider:
	$(KCTL) apply -f ../../crossplane/providers/aws/runtime-config.yaml
	$(KCTL) apply -f ../../crossplane/providers/aws/providers.yaml
	$(KCTL) wait provider.pkg.crossplane.io/provider-family-aws provider.pkg.crossplane.io/provider-aws-s3 provider.pkg.crossplane.io/provider-aws-rds --for=condition=Healthy=True --timeout=600s
	$(KCTL) apply -f ../../crossplane/providers/aws/mrap.yaml
	$(call wait_provider_pod,provider-aws-s3)
	$(call wait_provider_pod,provider-aws-rds)
	$(call wait_config_settled,clusterproviderconfig.aws.m.upbound.io/aws)
	@arn=$$(terraform -chdir=$(AUTH_TF) output -raw provider_role_arn) && test -n "$$arn" && sed "s|__PROVIDER_ROLE_ARN__|$$arn|" ../../crossplane/providers/aws/cluster-provider-config.yaml | $(KCTL) apply -f -

aws-verify:
	@bucket=$$(terraform -chdir=$(AUTH_TF) output -raw verify_bucket_name) && test -n "$$bucket" && sed "s|__VERIFY_BUCKET_NAME__|$$bucket|" ../../crossplane/verify/aws-bucket.yaml | $(KCTL) apply -f -
	$(KCTL) -n idp-verify wait bucket.s3.aws.m.upbound.io/verify --for=condition=Ready --timeout=300s
	$(KCTL) -n idp-verify get bucket.s3.aws.m.upbound.io/verify

aws-verify-delete:
	$(KCTL) -n idp-verify delete bucket.s3.aws.m.upbound.io/verify --wait

# ADR-0017: re-adopt an RDS instance after a control plane rebuild. The new MR
# cannot create (DBInstanceAlreadyExists), so look up the AWS-assigned
# resource ID and set it as the external name. The rebuilt control plane also
# generated a new master password, and the provider cannot read the old one
# back from RDS, so push the new one; otherwise the connection Secret holds a
# password RDS never received. The password reaches the AWS CLI through a
# private temporary file, removed on exit, never on the command line.
.PHONY: rds-readopt
rds-readopt:
	@test -n "$(NS)" && test -n "$(NAME)" || { echo "usage: make rds-readopt NS=<namespace> NAME=<database>"; exit 1; }
	@id=$$(aws rds describe-db-instances --region us-east-1 --db-instance-identifier idp-$(NS)-$(NAME) --query 'DBInstances[0].DbiResourceId' --output text) && test -n "$$id" && \
	mr=$$($(KCTL) -n $(NS) get instance.rds.aws.m.upbound.io -l crossplane.io/composite=$(NAME) -o name) && test -n "$$mr" && \
	$(KCTL) -n $(NS) annotate $$mr crossplane.io/external-name=$$id --overwrite
	@until $(KCTL) -n $(NS) get secret $(NAME)-master >/dev/null 2>&1; do sleep 5; done
	@req=$$(mktemp) && chmod 600 $$req && trap 'rm -f '$$req EXIT && \
	$(KCTL) -n $(NS) get secret $(NAME)-master -o jsonpath='{.data.password}' | python3 -c 'import base64,json,sys; print(json.dumps({"DBInstanceIdentifier": sys.argv[1], "MasterUserPassword": base64.b64decode(sys.stdin.read()).decode(), "ApplyImmediately": True}))' idp-$(NS)-$(NAME) > $$req && \
	aws rds modify-db-instance --region us-east-1 --cli-input-json file://$$req --query 'DBInstance.PendingModifiedValues' --output json

# Sub-providers installed for the current phase; must match providers.yaml.
AZURE_SUBPROVIDERS := provider-azure-dbforpostgresql

.PHONY: azure-provider azure-verify azure-verify-delete

azure-provider:
	$(KCTL) apply -f ../../crossplane/providers/azure/runtime-config.yaml
	$(KCTL) apply -f ../../crossplane/providers/azure/providers.yaml
	$(KCTL) wait provider.pkg.crossplane.io/provider-family-azure $(addprefix provider.pkg.crossplane.io/,$(AZURE_SUBPROVIDERS)) --for=condition=Healthy=True --timeout=600s
	$(KCTL) apply -f ../../crossplane/providers/azure/mrap.yaml
	$(call wait_provider_pod,provider-family-azure)
	for p in $(AZURE_SUBPROVIDERS); do until $(KCTL) -n crossplane-system get pod -l pkg.crossplane.io/provider=$$p -o name | grep -q .; do sleep 2; done; $(KCTL) -n crossplane-system wait pod -l pkg.crossplane.io/provider=$$p --for=condition=Ready --timeout=600s || exit 1; done
	$(call wait_config_settled,clusterproviderconfig.azure.m.upbound.io/azure)
	@client=$$(terraform -chdir=$(AZURE_AUTH_TF) output -raw client_id) && tenant=$$(terraform -chdir=$(AZURE_AUTH_TF) output -raw tenant_id) && sub=$$(terraform -chdir=$(AZURE_AUTH_TF) output -raw subscription_id) && test -n "$$client" && test -n "$$tenant" && test -n "$$sub" && sed -e "s|__AZURE_CLIENT_ID__|$$client|" -e "s|__AZURE_TENANT_ID__|$$tenant|" -e "s|__AZURE_SUBSCRIPTION_ID__|$$sub|" ../../crossplane/providers/azure/cluster-provider-config.yaml | $(KCTL) apply -f -
	@sub=$$(terraform -chdir=$(AZURE_AUTH_TF) output -raw subscription_id) && test -n "$$sub" && sed "s|__AZURE_SUBSCRIPTION_ID__|$$sub|" ../../crossplane/providers/azure/platform-azure-subscription.yaml | $(KCTL) apply -f -

azure-verify:
	$(KCTL) apply -f ../../crossplane/verify/azure-resource-group.yaml
	$(KCTL) -n idp-verify wait resourcegroup.azure.m.upbound.io/verify --for=condition=Ready --timeout=300s
	$(KCTL) -n idp-verify get resourcegroup.azure.m.upbound.io/verify

azure-verify-delete:
	$(KCTL) -n idp-verify delete resourcegroup.azure.m.upbound.io/verify --wait

# Sub-providers installed for the current phase; must match providers.yaml.
GCP_SUBPROVIDERS := provider-gcp-storage provider-gcp-sql

.PHONY: gcp-provider gcp-adc gcp-verify gcp-verify-delete

# ADR-0001: the external_account config holds no key material, so it is a
# ConfigMap, generated from crossplane-auth outputs and never committed. The
# project ID EnvironmentConfig is applied here too, outside Argo (ADR-0003).
gcp-adc:
	@terraform -chdir=$(GCP_AUTH_TF) output -raw credential_config > /dev/null
	terraform -chdir=$(GCP_AUTH_TF) output -raw credential_config | $(KCTL) -n crossplane-system create configmap idp-gcp-adc --from-file=credential-config.json=/dev/stdin --dry-run=client -o yaml | $(KCTL) apply -f -
	@project=$$(terraform -chdir=$(GCP_AUTH_TF) output -raw project_id) && test -n "$$project" && sed "s|__GCP_PROJECT_ID__|$$project|" ../../crossplane/providers/gcp/platform-gcp-project.yaml | $(KCTL) apply -f -

gcp-provider: gcp-adc
	$(KCTL) apply -f ../../crossplane/providers/gcp/runtime-config.yaml
	$(KCTL) apply -f ../../crossplane/providers/gcp/providers.yaml
	$(KCTL) wait provider.pkg.crossplane.io/provider-family-gcp $(addprefix provider.pkg.crossplane.io/,$(GCP_SUBPROVIDERS)) --for=condition=Healthy=True --timeout=600s
	$(KCTL) apply -f ../../crossplane/providers/gcp/mrap.yaml
	for p in $(GCP_SUBPROVIDERS); do until $(KCTL) -n crossplane-system get pod -l pkg.crossplane.io/provider=$$p -o name | grep -q .; do sleep 2; done; $(KCTL) -n crossplane-system wait pod -l pkg.crossplane.io/provider=$$p --for=condition=Ready --timeout=600s || exit 1; done
	$(call wait_config_settled,clusterproviderconfig.gcp.m.upbound.io/gcp)
	@project=$$(terraform -chdir=$(GCP_AUTH_TF) output -raw project_id) && test -n "$$project" && sed "s|__GCP_PROJECT_ID__|$$project|" ../../crossplane/providers/gcp/cluster-provider-config.yaml | $(KCTL) apply -f -

gcp-verify:
	@bucket=$$(terraform -chdir=$(GCP_AUTH_TF) output -raw verify_bucket_name) && test -n "$$bucket" && sed "s|__VERIFY_BUCKET_NAME__|$$bucket|" ../../crossplane/verify/gcp-bucket.yaml | $(KCTL) apply -f -
	$(KCTL) -n idp-verify wait bucket.storage.gcp.m.upbound.io/verify --for=condition=Ready --timeout=300s
	$(KCTL) -n idp-verify get bucket.storage.gcp.m.upbound.io/verify

gcp-verify-delete:
	$(KCTL) -n idp-verify delete bucket.storage.gcp.m.upbound.io/verify --wait

.PHONY: functions platform-apis

functions:
	$(KCTL) apply -f ../../crossplane/functions/functions.yaml
	$(KCTL) wait function.pkg.crossplane.io --all --for=condition=Healthy=True --timeout=600s

platform-apis:
	$(KCTL) apply -f ../../crossplane/environment/platform-regions.yaml
	$(KCTL) apply -f ../../crossplane/xrds/
	$(KCTL) wait xrd --all --for=condition=Established=True --timeout=300s
	$(KCTL) apply -f ../../crossplane/compositions/

ARGOCD_CHART_VERSION := 10.9.2
DEPLOY_KEY           := $(HOME)/.config/idp-platform/argocd-deploy-key
REPO_URL             := git@github.com:jordann6/idp-platform.git

.PHONY: argocd-install argocd-repo argocd-root

argocd-install:
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install argocd argo/argo-cd --version $(ARGOCD_CHART_VERSION) --namespace argocd --create-namespace --kubeconfig $(KUBECONFIG) --kube-context idp-k3s --values argocd/values.yaml --wait

# ADR-0018: read-only deploy key scoped to this repo, loaded from the Mac.
# The private key never enters git.
argocd-repo:
	@test -f $(DEPLOY_KEY) || (echo "Missing $(DEPLOY_KEY). See ADR-0018." && exit 1)
	$(KCTL) -n argocd create secret generic repo-idp-platform --from-literal=type=git --from-literal=url=$(REPO_URL) --from-file=sshPrivateKey=$(DEPLOY_KEY) --dry-run=client -o yaml | $(KCTL) label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | $(KCTL) apply -f -

argocd-root:
	$(KCTL) apply -f ../../argocd/projects/
	$(KCTL) apply -f ../../argocd/app-of-apps.yaml

BACKSTAGE_CHART_VERSION := 2.10.2
BACKSTAGE_TOKEN         := $(HOME)/.config/idp-platform/backstage-github-token

.PHONY: backstage-token backstage-install

# ADR-0019: fine-grained PAT limited to this repo (contents and pull requests),
# loaded from the Mac. The token never enters git.
backstage-token:
	@test -s $(BACKSTAGE_TOKEN) || (echo "Missing $(BACKSTAGE_TOKEN). See ADR-0019." && exit 1)
	$(KCTL) create namespace backstage --dry-run=client -o yaml | $(KCTL) apply -f -
	$(KCTL) -n backstage create secret generic backstage-github --from-file=GITHUB_TOKEN=$(BACKSTAGE_TOKEN) --dry-run=client -o yaml | $(KCTL) apply -f -

backstage-install:
	helm repo add backstage https://backstage.github.io/charts --force-update
	helm upgrade --install backstage backstage/backstage --version $(BACKSTAGE_CHART_VERSION) --namespace backstage --create-namespace --kubeconfig $(KUBECONFIG) --kube-context idp-k3s --values backstage/values.yaml --wait --timeout 10m

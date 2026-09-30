VM            := idp-k3s
KUBECONFIG    := $(HOME)/.kube/idp-k3s.yaml
KCTL          := kubectl --kubeconfig $(KUBECONFIG) --context idp-k3s
ISSUER_TF     := ../aws/oidc-issuer
DISCOVERY_DIR := $(ISSUER_TF)/discovery

# Provider Healthy can read True before the runtime pod exists, so also wait
# for the provider pod itself to be Ready. Crossplane v2 keeps a provider's
# deployment at zero replicas until one of its MRDs is active, so the MRAP
# must be applied before this wait or it never returns.
define wait_provider_pod
	until $(KCTL) -n crossplane-system get pod -l pkg.crossplane.io/provider=$(1) -o name | grep -q .; do sleep 2; done
	$(KCTL) -n crossplane-system wait pod -l pkg.crossplane.io/provider=$(1) --for=condition=Ready --timeout=600s
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
	@count=$$($(KCTL) get managed -A --no-headers 2>/dev/null | wc -l | tr -d ' '); \
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
	$(KCTL) apply -f ../../crossplane/providers/aws/cluster-provider-config.yaml

aws-verify:
	$(KCTL) apply -f ../../crossplane/verify/aws-bucket.yaml
	$(KCTL) -n idp-verify wait bucket.s3.aws.m.upbound.io/verify --for=condition=Ready --timeout=300s
	$(KCTL) -n idp-verify get bucket.s3.aws.m.upbound.io/verify

aws-verify-delete:
	$(KCTL) -n idp-verify delete bucket.s3.aws.m.upbound.io/verify --wait

.PHONY: azure-provider azure-verify azure-verify-delete

azure-provider:
	$(KCTL) apply -f ../../crossplane/providers/azure/runtime-config.yaml
	$(KCTL) apply -f ../../crossplane/providers/azure/providers.yaml
	$(KCTL) wait provider.pkg.crossplane.io/provider-family-azure --for=condition=Healthy=True --timeout=600s
	$(KCTL) apply -f ../../crossplane/providers/azure/mrap.yaml
	$(call wait_provider_pod,provider-family-azure)
	$(KCTL) apply -f ../../crossplane/providers/azure/cluster-provider-config.yaml

azure-verify:
	$(KCTL) apply -f ../../crossplane/verify/azure-resource-group.yaml
	$(KCTL) -n idp-verify wait resourcegroup.azure.m.upbound.io/verify --for=condition=Ready --timeout=300s
	$(KCTL) -n idp-verify get resourcegroup.azure.m.upbound.io/verify

azure-verify-delete:
	$(KCTL) -n idp-verify delete resourcegroup.azure.m.upbound.io/verify --wait

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

OC     := oc
HELM   := helm
HCP    := hcp

# --- Hosted cluster settings ---
CLUSTER_NAME       := hosted-vlan100
CLUSTER_NS         := clusters-$(CLUSTER_NAME)
VLAN_ID            := 100
NAD_NAME           := localnet-vlan100

# --- Infrastructure (reuses logical-segmentation chart) ---
INFRA_CHART        := ../logical-segmentation/helm/vlan-segmentation
INFRA_RELEASE      := vlan-seg

# --- Worker VM sizing ---
VM_CORES           := 4
VM_MEMORY          := 8Gi
NODE_POOL_REPLICAS := 1

# --- Kubeconfig for the hosted cluster ---
KUBECONFIG_HC      := $(CLUSTER_NAME)-kubeconfig

.PHONY: help check-tools enable-hcp \
        deploy-infra deploy-cudn create-cluster wait-cluster get-kubeconfig deploy-test \
        status teardown teardown-test teardown-cluster teardown-cudn teardown-infra

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

check-tools: ## Verify required CLI tools are installed
	@which $(OC)   > /dev/null || (echo "Error: oc not found"   && exit 1)
	@which $(HELM) > /dev/null || (echo "Error: helm not found" && exit 1)
	@which $(HCP)  > /dev/null || (echo "Error: hcp not found"  && exit 1)

enable-hcp: check-tools ## Enable Hypershift (HCP) in the MultiClusterEngine resource
	@$(OC) patch mce multiclusterengine --type=merge \
		-p '{"spec":{"overrides":{"components":[{"name":"hypershift","enabled":true}]}}}'
	@echo "Waiting for MCE and HCP Operator pods to become available..."
	@$(OC) wait multiclusterengine/multiclusterengine --for=condition=Available --timeout=10m
	@$(OC) wait deployment/operator -n hypershift --for=condition=Available --timeout=5m
	@echo "Creating HCP credentials for ACM..."
	@$(OC) apply -f hcp-credentials.yaml

deploy-infra: check-tools ## Deploy OVS bridge + NNCPs + MetalLB (reuses logical-segmentation chart)
	@echo "Deploying network infrastructure..."
	@$(HELM) upgrade --install $(INFRA_RELEASE) $(INFRA_CHART) --set test.enabled=false
	@echo "Waiting for NNCPs to reconcile..."
	@sleep 30
	@$(OC) wait nncp -l app.kubernetes.io/instance=$(INFRA_RELEASE) \
		--for=condition=Available --timeout=120s
	@echo "Infrastructure ready"

deploy-cudn: check-tools ## Deploy ClusterUserDefinedNetwork (localnet VLAN)
	@$(OC) apply -f manifests/cudn-vlan100.yaml
	@echo "CUDN $(NAD_NAME) created (NAD will be auto-generated in $(CLUSTER_NS) when namespace exists)"

create-cluster: check-tools ## Create hosted cluster (API via LoadBalancer, HCP private router)
	@if $(OC) get hostedcluster $(CLUSTER_NAME) -n clusters >/dev/null 2>&1; then \
		echo "HostedCluster $(CLUSTER_NAME) already exists, skipping creation"; \
	else \
		echo "Extracting pull-secret from hosting cluster..." && \
		$(OC) get secret/pull-secret -n openshift-config \
			-o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/hcp-pull-secret.json && \
		RELEASE_IMAGE=$$($(OC) get clusterversion version -o jsonpath='{.status.desired.image}') && \
		echo "Creating hosted cluster (release: $$RELEASE_IMAGE)..." && \
		$(HCP) create cluster kubevirt \
			--name $(CLUSTER_NAME) \
			--release-image $$RELEASE_IMAGE \
			--pull-secret /tmp/hcp-pull-secret.json \
			--node-pool-replicas $(NODE_POOL_REPLICAS) \
			--memory $(VM_MEMORY) \
			--cores $(VM_CORES) \
			--additional-network name:$(NAD_NAME) \
			--infra-availability-policy SingleReplica \
			--control-plane-availability-policy SingleReplica && \
		rm -f /tmp/hcp-pull-secret.json && \
		echo "Hosted cluster creation started"; \
	fi

wait-cluster: ## Wait for hosted cluster and worker nodes to be ready
	@echo "Waiting for HostedCluster $(CLUSTER_NAME) control plane (up to 30m)..."
	@$(OC) wait hostedcluster/$(CLUSTER_NAME) -n clusters \
		--for=condition=Available --timeout=30m
	@echo "Control plane is available. Waiting for NodePool workers (up to 30m)..."
	@$(OC) wait nodepool/$(CLUSTER_NAME) -n clusters \
		--for=condition=Ready --timeout=30m
	@echo "Hosted cluster $(CLUSTER_NAME) is fully ready (control plane + workers)"

get-kubeconfig: ## Extract kubeconfig for the hosted cluster
	@$(HCP) create kubeconfig --name $(CLUSTER_NAME) > $(KUBECONFIG_HC)
	@echo "Kubeconfig saved to $(KUBECONFIG_HC)"

deploy-test: get-kubeconfig ## Deploy test workloads on the hosted cluster
	@echo "Deploying test workloads on $(CLUSTER_NAME)..."
	@$(OC) --kubeconfig=$(KUBECONFIG_HC) apply -f manifests/test-workloads.yaml
	@echo "Waiting for echo deployment to be ready..."
	@$(OC) --kubeconfig=$(KUBECONFIG_HC) wait deployment/echo -n test-echo \
		--for=condition=Available --timeout=5m
	@echo "Test workloads deployed. Service details:"
	@$(OC) --kubeconfig=$(KUBECONFIG_HC) get svc echo -n test-echo

deploy: enable-hcp deploy-infra deploy-cudn create-cluster wait-cluster get-kubeconfig deploy-test ## Full deploy

teardown-test: ## Remove test workloads from hosted cluster
	@if [ -f $(KUBECONFIG_HC) ]; then \
		echo "Removing test workloads..."; \
		$(OC) --kubeconfig=$(KUBECONFIG_HC) delete -f manifests/test-workloads.yaml --ignore-not-found; \
	else \
		echo "No kubeconfig found, skipping test cleanup"; \
	fi

teardown-cluster: ## Destroy the hosted cluster
	@echo "Destroying hosted cluster $(CLUSTER_NAME)..."
	@$(HCP) destroy cluster kubevirt --name $(CLUSTER_NAME) || true
	@echo "Waiting for namespace $(CLUSTER_NS) to be removed..."
	@$(OC) wait namespace/$(CLUSTER_NS) --for=delete --timeout=15m 2>/dev/null || true
	@rm -f $(KUBECONFIG_HC)
	@echo "Hosted cluster destroyed"

teardown-cudn: ## Remove the ClusterUserDefinedNetwork
	@$(OC) delete -f manifests/cudn-vlan100.yaml --ignore-not-found 2>/dev/null || true

teardown-infra: ## Teardown OVS bridge + NNCPs + MetalLB
	@echo "Tearing down network infrastructure..."
	@$(HELM) upgrade $(INFRA_RELEASE) $(INFRA_CHART) --reuse-values --set cleanup=true
	@echo "Waiting 60s for NNCPs to reconcile cleanup..."
	@sleep 60
	@$(OC) wait nncp -l app.kubernetes.io/instance=$(INFRA_RELEASE) \
		--for=condition=Available --timeout=120s
	@echo "NNCPs reconciled, uninstalling Helm release..."
	@$(HELM) uninstall $(INFRA_RELEASE) --wait

teardown: teardown-test teardown-cluster teardown-cudn teardown-infra ## Full teardown (reverse order)
	@echo "Full teardown complete"
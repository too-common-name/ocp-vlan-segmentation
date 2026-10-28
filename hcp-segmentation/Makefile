OC     := oc
HELM   := helm
HCP    := hcp

INFRA_CHART        := ../namespace-segmentation/helm/vlan-segmentation
INFRA_RELEASE      := vlan-seg
CHART              := helm/hcp-cluster

VM_CORES           := 4
VM_MEMORY          := 8Gi
NODE_POOL_REPLICAS := 1

.PHONY: help check-tools enable-hcp \
        deploy-infra deploy-vlan100 deploy-vlan200 deploy \
        teardown-vlan100 teardown-vlan200 teardown-infra teardown \
        status

help: ## Show this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
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

teardown-infra: ## Teardown OVS bridge + NNCPs + MetalLB
	@echo "Waiting for hosted cluster namespaces to be fully removed..."
	@$(OC) wait namespace/clusters-hosted-vlan100 --for=delete --timeout=15m 2>/dev/null || true
	@$(OC) wait namespace/clusters-hosted-vlan200 --for=delete --timeout=15m 2>/dev/null || true
	@echo "Tearing down network infrastructure..."
	@if $(HELM) status $(INFRA_RELEASE) >/dev/null 2>&1; then \
		$(HELM) upgrade $(INFRA_RELEASE) $(INFRA_CHART) --reuse-values --set cleanup=true; \
		echo "Waiting 60s for NNCPs to reconcile cleanup..."; \
		sleep 60; \
		$(OC) wait nncp -l app.kubernetes.io/instance=$(INFRA_RELEASE) \
			--for=condition=Available --timeout=120s; \
		$(HELM) uninstall $(INFRA_RELEASE) --wait; \
	else \
		echo "Helm release $(INFRA_RELEASE) not found, skipping"; \
	fi

deploy-vlan100: check-tools ## Deploy hosted-vlan100 (CUDN + cluster + test workloads)
	@echo "Applying CUDN for VLAN 100..."
	@$(HELM) template hosted-vlan100 $(CHART) \
		--set clusterName=hosted-vlan100,vlanId=100 \
		-s templates/cudn.yaml | $(OC) apply -f -
	@if $(OC) get hostedcluster hosted-vlan100 -n clusters >/dev/null 2>&1; then \
		echo "HostedCluster hosted-vlan100 already exists, skipping creation"; \
	else \
		echo "Extracting pull-secret..." && \
		$(OC) get secret/pull-secret -n openshift-config \
			-o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/hcp-pull-secret.json && \
		RELEASE_IMAGE=$$($(OC) get clusterversion version -o jsonpath='{.status.desired.image}') && \
		echo "Creating hosted cluster hosted-vlan100 (release: $$RELEASE_IMAGE)..." && \
		$(HCP) create cluster kubevirt \
			--name hosted-vlan100 \
			--release-image $$RELEASE_IMAGE \
			--pull-secret /tmp/hcp-pull-secret.json \
			--node-pool-replicas $(NODE_POOL_REPLICAS) \
			--memory $(VM_MEMORY) \
			--cores $(VM_CORES) \
			--additional-network name:localnet-vlan100 \
			--infra-availability-policy SingleReplica \
			--control-plane-availability-policy SingleReplica && \
		rm -f /tmp/hcp-pull-secret.json; \
	fi
	@echo "Waiting for hosted-vlan100 control plane (up to 30m)..."
	@$(OC) wait hostedcluster/hosted-vlan100 -n clusters --for=condition=Available --timeout=30m
	@echo "Waiting for NodePool workers (up to 30m)..."
	@$(OC) wait nodepool/hosted-vlan100 -n clusters --for=condition=Ready --timeout=30m
	@$(HCP) create kubeconfig --name hosted-vlan100 > hosted-vlan100-kubeconfig
	@echo "Deploying test workloads on hosted-vlan100..."
	@$(HELM) template hosted-vlan100 $(CHART) \
		--set clusterName=hosted-vlan100,vlanId=100 \
		-s templates/test-workloads.yaml | $(OC) --kubeconfig=hosted-vlan100-kubeconfig apply -f -
	@$(OC) --kubeconfig=hosted-vlan100-kubeconfig wait deployment/echo -n test-echo \
		--for=condition=Available --timeout=5m
	@echo "hosted-vlan100 ready. Service:"
	@$(OC) --kubeconfig=hosted-vlan100-kubeconfig get svc echo -n test-echo

teardown-vlan100: ## Teardown hosted-vlan100
	@echo "Tearing down hosted-vlan100..."
	@if [ -f hosted-vlan100-kubeconfig ]; then \
		$(OC) --kubeconfig=hosted-vlan100-kubeconfig delete ns test-echo --ignore-not-found 2>/dev/null || true; \
	fi
	@if $(OC) get hostedcluster hosted-vlan100 -n clusters >/dev/null 2>&1; then \
		$(HCP) destroy cluster kubevirt --name hosted-vlan100; \
	else \
		echo "HostedCluster hosted-vlan100 not found, skipping destroy"; \
	fi
	@$(OC) wait namespace/clusters-hosted-vlan100 --for=delete --timeout=15m 2>/dev/null || true
	@$(HELM) template hosted-vlan100 $(CHART) \
		--set clusterName=hosted-vlan100,vlanId=100 \
		-s templates/cudn.yaml | $(OC) delete -f - --ignore-not-found 2>/dev/null || true
	@rm -f hosted-vlan100-kubeconfig

deploy-vlan200: check-tools ## Deploy hosted-vlan200 (CUDN + cluster + test workloads)
	@echo "Applying CUDN for VLAN 200..."
	@$(HELM) template hosted-vlan200 $(CHART) \
		--set clusterName=hosted-vlan200,vlanId=200 \
		-s templates/cudn.yaml | $(OC) apply -f -
	@if $(OC) get hostedcluster hosted-vlan200 -n clusters >/dev/null 2>&1; then \
		echo "HostedCluster hosted-vlan200 already exists, skipping creation"; \
	else \
		echo "Extracting pull-secret..." && \
		$(OC) get secret/pull-secret -n openshift-config \
			-o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/hcp-pull-secret.json && \
		RELEASE_IMAGE=$$($(OC) get clusterversion version -o jsonpath='{.status.desired.image}') && \
		echo "Creating hosted cluster hosted-vlan200 (release: $$RELEASE_IMAGE)..." && \
		$(HCP) create cluster kubevirt \
			--name hosted-vlan200 \
			--release-image $$RELEASE_IMAGE \
			--pull-secret /tmp/hcp-pull-secret.json \
			--node-pool-replicas $(NODE_POOL_REPLICAS) \
			--memory $(VM_MEMORY) \
			--cores $(VM_CORES) \
			--additional-network name:localnet-vlan200 \
			--infra-availability-policy SingleReplica \
			--control-plane-availability-policy SingleReplica && \
		rm -f /tmp/hcp-pull-secret.json; \
	fi
	@echo "Waiting for hosted-vlan200 control plane (up to 30m)..."
	@$(OC) wait hostedcluster/hosted-vlan200 -n clusters --for=condition=Available --timeout=30m
	@echo "Waiting for NodePool workers (up to 30m)..."
	@$(OC) wait nodepool/hosted-vlan200 -n clusters --for=condition=Ready --timeout=30m
	@$(HCP) create kubeconfig --name hosted-vlan200 > hosted-vlan200-kubeconfig
	@echo "Deploying test workloads on hosted-vlan200..."
	@$(HELM) template hosted-vlan200 $(CHART) \
		--set clusterName=hosted-vlan200,vlanId=200 \
		-s templates/test-workloads.yaml | $(OC) --kubeconfig=hosted-vlan200-kubeconfig apply -f -
	@$(OC) --kubeconfig=hosted-vlan200-kubeconfig wait deployment/echo -n test-echo \
		--for=condition=Available --timeout=5m
	@echo "hosted-vlan200 ready. Service:"
	@$(OC) --kubeconfig=hosted-vlan200-kubeconfig get svc echo -n test-echo

teardown-vlan200: ## Teardown hosted-vlan200
	@echo "Tearing down hosted-vlan200..."
	@if [ -f hosted-vlan200-kubeconfig ]; then \
		$(OC) --kubeconfig=hosted-vlan200-kubeconfig delete ns test-echo --ignore-not-found 2>/dev/null || true; \
	fi
	@if $(OC) get hostedcluster hosted-vlan200 -n clusters >/dev/null 2>&1; then \
		$(HCP) destroy cluster kubevirt --name hosted-vlan200; \
	else \
		echo "HostedCluster hosted-vlan200 not found, skipping destroy"; \
	fi
	@$(OC) wait namespace/clusters-hosted-vlan200 --for=delete --timeout=15m 2>/dev/null || true
	@$(HELM) template hosted-vlan200 $(CHART) \
		--set clusterName=hosted-vlan200,vlanId=200 \
		-s templates/cudn.yaml | $(OC) delete -f - --ignore-not-found 2>/dev/null || true
	@rm -f hosted-vlan200-kubeconfig

deploy: enable-hcp deploy-infra deploy-vlan100 deploy-vlan200 ## Full deploy (infra + both clusters)

teardown: teardown-vlan200 teardown-vlan100 teardown-infra ## Full teardown (reverse order)
	@echo "Full teardown complete"

status: ## Show cluster status and VIPs
	@$(OC) get hostedcluster,nodepool -n clusters 2>/dev/null || true
	@echo "---"
	@$(OC) get svc -n clusters-hosted-vlan100 --no-headers 2>/dev/null | grep LoadBalancer || true
	@$(OC) get svc -n clusters-hosted-vlan200 --no-headers 2>/dev/null | grep LoadBalancer || true

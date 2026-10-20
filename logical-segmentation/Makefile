CHART   := helm/vlan-segmentation
RELEASE := vlan-seg
HELM   := helm

.PHONY: help check-tools deploy-ovs deploy-vlan teardown render-ovs render-vlan

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

check-tools:  ## Verify required CLI tools are installed
	@which $(HELM) > /dev/null || (echo "Error: helm not found" && exit 1)

deploy-ovs: check-tools ## Deploy OVS bridge scenario
	@$(HELM) upgrade --install $(RELEASE) $(CHART)

deploy-vlan: check-tools ## Deploy VLAN interfaces scenario
	@$(HELM) upgrade --install $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml


teardown: check-tools ## Teardown the setup
	@$(HELM) upgrade $(RELEASE) $(CHART) --reuse-values --set cleanup=true
	@echo "Waiting 60s for NNCPs to reconcile cleanup..."
	@sleep 60
	oc wait nncp -l app.kubernetes.io/instance=$(RELEASE) \
	  --for=condition=Available --timeout=120s
	@echo "NNCPs reconciled, uninstalling Helm release..."
	@$(HELM) uninstall $(RELEASE) --wait

render-ovs: check-tools ## Render manifests for OVS scenario
	@$(HELM) template $(RELEASE) $(CHART)

render-vlan: check-tools ## Render manifests for VLAN interfaces scenario
	@$(HELM) template $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml

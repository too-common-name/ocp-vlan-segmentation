CHART   := helm/cudn-segmentation
RELEASE := cudn-seg
HELM    := helm

.PHONY: help check-tools deploy teardown render

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

check-tools: ## Verify required CLI tools are installed
	@which $(HELM) > /dev/null || (echo "Error: helm not found" && exit 1)

deploy: check-tools ## Deploy CUDN localnet scenario
	@$(HELM) upgrade --install $(RELEASE) $(CHART)

teardown: check-tools ## Teardown the setup
	@$(HELM) upgrade $(RELEASE) $(CHART) --reuse-values --set cleanup=true
	@echo "Waiting 30s for CUDNs and NNCP to reconcile cleanup..."
	@sleep 30
	oc wait nncp -l app.kubernetes.io/instance=$(RELEASE) \
	  --for=condition=Available --timeout=120s
	@echo "NNCPs reconciled, uninstalling Helm release..."
	@$(HELM) uninstall $(RELEASE) --wait

render: check-tools ## Render manifests (dry-run)
	@$(HELM) template $(RELEASE) $(CHART)

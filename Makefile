CHART   := helm/vlan-segmentation
RELEASE := vlan-seg


deploy-ovs:
	helm upgrade --install $(RELEASE) $(CHART)

deploy-vlan:
	helm upgrade --install $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml


teardown:
	helm upgrade $(RELEASE) $(CHART) --reuse-values --set cleanup=true
	@echo "Waiting 60s for NNCPs to reconcile cleanup..."
	@sleep 60
	oc wait nncp -l app.kubernetes.io/instance=$(RELEASE) \
	  --for=condition=Available --timeout=120s
	@echo "NNCPs reconciled, uninstalling Helm release..."
	helm uninstall $(RELEASE) --wait


render-ovs:
	helm template $(RELEASE) $(CHART)

render-vlan:
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml

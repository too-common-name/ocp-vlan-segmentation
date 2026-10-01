CHART   := helm/vlan-segmentation
RELEASE := vlan-seg

# ─── Deploy ─────────────────────────────────────────────────────────

deploy-ovs:
	helm upgrade --install $(RELEASE) $(CHART)

deploy-vlan:
	helm upgrade --install $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml

deploy-linuxbr:
	helm upgrade --install $(RELEASE) $(CHART) -f $(CHART)/values-linux-bridge.yaml

# ─── Teardown (state: absent → wait → uninstall) ───────────────────

teardown:
	helm upgrade $(RELEASE) $(CHART) --reuse-values --set cleanup=true
	@echo "Waiting for NMState to remove interfaces..."
	@sleep 60
	helm uninstall $(RELEASE) --wait

# ─── Render (dry-run) ──────────────────────────────────────────────

render-ovs:
	helm template $(RELEASE) $(CHART)

render-vlan:
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-vlan-subinterfaces.yaml

render-linuxbr:
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-linux-bridge.yaml

CHART      := helm/charts/data-sync
DUMMY_PASS ?= dummy-ci-only

.PHONY: lint template kustomize ansible-lint check
lint:
	helm lint $(CHART)
	helm lint $(CHART) -f $(CHART)/values.yaml -f $(CHART)/values.staging.yaml --set-string redis.password=$(DUMMY_PASS)
	helm lint $(CHART) -f $(CHART)/values.yaml -f $(CHART)/values.production.yaml --set-string redis.password=$(DUMMY_PASS)

template:
	helm template data-sync $(CHART) -f $(CHART)/values.yaml > /dev/null
	helm template data-sync $(CHART) -f $(CHART)/values.yaml -f $(CHART)/values.staging.yaml --set-string redis.password=$(DUMMY_PASS) > /dev/null
	helm template data-sync $(CHART) -f $(CHART)/values.yaml -f $(CHART)/values.production.yaml --set-string redis.password=$(DUMMY_PASS) > /dev/null

kustomize:
	REDIS_PASSWORD=$(DUMMY_PASS) standard/data-sync/production/render.sh
	kustomize build standard/data-sync/production

ansible-lint:
	cd ansible && ansible-lint

check: lint template kustomize ansible-lint

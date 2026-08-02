HELM_DOCS_VERSION := v1.14.2
HELM_SCHEMA_VERSION := 0.18.1

.PHONY: docs schema lint lint-values-coverage template test

## Generate per-chart README.md from README.md.gotmpl + values.yaml comments.
docs:
	docker run --rm -v "$(CURDIR):/helm-docs" -u $(shell id -u) jnorwood/helm-docs:$(HELM_DOCS_VERSION) -c charts

## Generate values.schema.json from values.yaml # @schema annotations.
schema:
	docker run --rm -v "$(CURDIR)/charts:/charts" -u $(shell id -u) -w /charts ghcr.io/dadav/helm-schema:$(HELM_SCHEMA_VERSION) -c /charts

## Lint all charts.
lint:
	helm lint charts/authup
	ct lint --config .github/configs/ct.yaml || true

## Every .Values.* referenced in templates must exist in values.yaml — a strict
## generated schema silently disables any feature whose key is missing.
lint-values-coverage:
	python3 scripts/check-values-coverage.py charts/authup

## Render the chart with every ci values file.
template:
	@for f in charts/authup/ci/*-values.yaml; do \
	  echo "=== $$f"; \
	  helm template test charts/authup -f "$$f" >/dev/null || exit 1; \
	done
	@echo "all ci values render"

test: lint template lint-values-coverage

# Usage: make <target> [ENV=dev]
ENV        ?= dev
TF_ENV     := terraform -chdir=infra/envs/$(ENV)
TF_FOUND   := terraform -chdir=infra/foundation

.PHONY: help bootstrap foundation init plan up down fmt validate lint data

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

bootstrap: ## One-time: create Terraform remote-state storage
	./infra/bootstrap/bootstrap.sh

foundation: ## One-time: persistent subscription budgets (never destroyed)
	$(TF_FOUND) init -backend-config=../backend.hcl -backend-config="key=foundation.tfstate"
	$(TF_FOUND) apply

init: ## Init the ephemeral environment root
	$(TF_ENV) init -backend-config=../../backend.hcl -backend-config="key=$(ENV).tfstate"

plan: ## Plan the ephemeral environment
	$(TF_ENV) plan

up: ## Create the environment (start of a work session)
	@date +%s > .up_started
	$(TF_ENV) apply -auto-approve
	@echo "up took $$(( $$(date +%s) - $$(cat .up_started) ))s"; rm -f .up_started

down: ## Destroy the environment (end of EVERY work session)
	$(TF_ENV) destroy -auto-approve

fmt: ## Format all Terraform
	terraform fmt -recursive infra

validate: ## Validate both Terraform roots
	$(TF_FOUND) validate
	$(TF_ENV) validate

lint: ## tflint + ruff
	tflint --recursive --chdir=infra --config=$(CURDIR)/.tflint.hcl
	uv run ruff check .

data: ## Download Sleep-EDF Expanded (8.1 GB) into data/sleep-edfx
	./scripts/download_sleep_edf.sh

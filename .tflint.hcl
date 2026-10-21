# One config for every Terraform directory. `make lint` and the pre-commit hook
# both point here explicitly, so local runs and commits apply the same rules.
# After changing a plugin version: tflint --init --config="$PWD/.tflint.hcl"

config {
  call_module_type = "local" # also lint the infra/modules/* code the roots call
}

# Built-in Terraform language rules. "recommended" covers typed variables,
# unused declarations, pinned provider versions, and required_version.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Azure-specific checks (VM sizes, SKUs, storage account names) from the provider schema.
# No deep_check: that would call Azure APIs and need credentials on every lint.
plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Stricter than "recommended": every input and output says what it is for.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# snake_case for resource, variable, output, and module names.
rule "terraform_naming_convention" {
  enabled = true
}

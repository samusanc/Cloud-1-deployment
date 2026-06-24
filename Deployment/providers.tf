terraform {
    required_version = ">= 1.6.0"

    required_providers {
        azurerm = {
            source = "hashicorp/azurerm"
            version = "~> 4.0"
        }
    }
}

provider "azurerm" {
    # Don't let Terraform auto-register Azure Resource Providers. On Cloud Shell /
    # restricted subscriptions you often lack permission, so it hangs on plan.
    # The core providers (Microsoft.Network, Microsoft.Compute) are normally
    # already registered; if apply ever complains one isn't, register it once with:
    #   az provider register --namespace Microsoft.Network --wait
    resource_provider_registrations = "none"
    features {}
}
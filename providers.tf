terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Estado local. Para trabajo en equipo conviene un backend remoto
  # (Azure Storage) y así evitar conflictos sobre el archivo de estado.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstatemod3"
  #   container_name       = "tfstate"
  #   key                  = "mod3-eva-final.tfstate"
  # }
}

provider "azurerm" {
  features {}

  # Si se deja en null, el provider toma la suscripción de la variable de
  # entorno ARM_SUBSCRIPTION_ID o de la sesión activa de `az login`.
  subscription_id = var.subscription_id
}

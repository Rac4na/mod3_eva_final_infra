terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Solo para esperar a que se propague el RBAC del Key Vault antes de
    # escribir el secreto. Ver keyvault.tf.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Estado remoto en Azure Storage. Es obligatorio para que el pipeline pueda
  # aplicar: un runner de GitHub arranca sin nada, y con estado local creería
  # que la infraestructura no existe e intentaría crearla de cero.
  #
  # El storage account se crea fuera de Terraform (con az CLI) a propósito: si
  # lo gestionara este mismo código, el estado tendría que existir antes de
  # poder crear el sitio donde se guarda.
  #
  # use_azuread_auth evita manejar la access key del storage account: el acceso
  # se concede con el rol Storage Blob Data Contributor sobre la cuenta.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate5fb84928"
    container_name       = "tfstate"
    key                  = "mod3-eva-final.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}

  # Si se deja en null, el provider toma la suscripción de la variable de
  # entorno ARM_SUBSCRIPTION_ID o de la sesión activa de `az login`.
  subscription_id = var.subscription_id
}

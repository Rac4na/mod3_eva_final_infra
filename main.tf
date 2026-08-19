resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project_name}"
  location = var.location
  tags     = var.tags
}

# Container Apps exige un workspace de Log Analytics para centralizar los logs
# de las réplicas. Sin esto no se puede crear el environment.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.project_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# El environment es la frontera de red y de observabilidad: todas las apps que
# viven dentro comparten red virtual y destino de logs.
resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${var.project_name}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

resource "azurerm_container_app" "this" {
  name                         = "ca-${var.project_name}"
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = var.tags

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "hello"
      image  = var.container_image
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "GREETING_NAME"
        value = var.greeting_name
      }

      # Reinicia la réplica si deja de responder.
      liveness_probe {
        transport = "HTTP"
        port      = var.container_port
        path      = "/health"
      }

      # Retira la réplica del balanceo hasta que esté lista para recibir tráfico.
      readiness_probe {
        transport = "HTTP"
        port      = var.container_port
        path      = "/health"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # El pipeline de CD del repo mod3_eva_final_app despliega cada commit con
  # `az containerapp update --image <repo>:<sha>`. Terraform vería ese tag como
  # una desviación y el siguiente `apply` lo revertiría a var.container_image,
  # deshaciendo el último despliegue. Aquí var.container_image queda como la
  # imagen con la que nace la app; a partir de entonces el tag lo manda el CD.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }
}

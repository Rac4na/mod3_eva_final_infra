# Identidad de la aplicación.
#
# Es *user assigned* y no *system assigned* a propósito. La identidad que nace
# junto a la Container App crearía una dependencia circular: Terraform necesita
# su principal_id para conceder el permiso sobre el Key Vault, pero la app
# necesita ese permiso concedido para resolver el secreto al arrancar. Creando
# la identidad por separado el orden queda lineal:
#
#   identidad  →  permiso de lectura  →  Container App
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.project_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

data "azurerm_client_config" "current" {}

locals {
  # El nombre de un Key Vault es único a nivel global y admite entre 3 y 24
  # caracteres, así que se le añade un sufijo derivado de la suscripción para
  # evitar colisiones con otras cuentas. El prefijo se recorta a 17 para que el
  # total (17 + 1 + 6) nunca pase de 24.
  kv_suffix = substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 6)
  kv_name   = "${substr("kv-${var.project_name}", 0, 17)}-${local.kv_suffix}"
}

resource "azurerm_key_vault" "this" {
  name                = local.kv_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Los permisos se gestionan con RBAC de Azure y no con access policies, que
  # es el modelo heredado. Así el control de acceso vive en el mismo sitio que
  # el del resto de recursos.
  rbac_authorization_enabled = true

  # Sin esto el nombre queda retenido 90 días tras un destroy y no se puede
  # recrear el vault igual. Con 7 días y sin purge protection, el entorno se
  # puede destruir y volver a levantar sin quedarse sin nombre.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# Permiso para que la app LEA el secreto. Es el rol mínimo: permite leer
# valores, no crearlos ni listar otros vaults.
resource "azurerm_role_assignment" "app_lee_secretos" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Permiso para que quien ejecuta Terraform CREE el secreto. Con RBAC activado,
# ser Owner de la suscripción no basta: hay que tener un rol sobre el plano de
# datos del vault.
resource "azurerm_role_assignment" "terraform_escribe_secretos" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Los role assignments de RBAC tardan en propagarse al plano de datos del
# vault. Sin esta espera, crear el secreto justo después falla con un 403
# aunque el permiso ya exista en el plano de control.
resource "time_sleep" "propagacion_rbac" {
  depends_on      = [azurerm_role_assignment.terraform_escribe_secretos]
  create_duration = "60s"
}

resource "azurerm_key_vault_secret" "demo" {
  name         = var.secret_name
  value        = var.secret_value
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [time_sleep.propagacion_rbac]
}

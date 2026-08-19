# mod3_eva_final_infra

Infraestructura como código (Terraform) para desplegar el microservicio
`/hello` en **Azure Container Apps**.

El código de la aplicación vive en un repositorio aparte:
**`mod3_eva_final_app`**. Este repositorio solo consume la imagen ya publicada
en Docker Hub.

## Recursos que crea

| Recurso | Para qué sirve |
|---|---|
| `azurerm_resource_group` | Contenedor lógico de todos los recursos |
| `azurerm_log_analytics_workspace` | Destino de los logs (lo exige el environment) |
| `azurerm_container_app_environment` | Frontera de red y observabilidad de las apps |
| `azurerm_container_app` | La aplicación, con ingress público en HTTPS |

```
Resource Group  (rg-mod3-eva-final)
 ├── Log Analytics Workspace   (log-mod3-eva-final)
 └── Container App Environment (cae-mod3-eva-final)
      └── Container App        (ca-mod3-eva-final)  → HTTPS público
```

## Estructura

```
.
├── providers.tf              # versiones y configuración del provider azurerm
├── variables.tf              # parámetros de entrada
├── main.tf                   # definición de los recursos
├── outputs.tf                # FQDN y URLs resultantes
└── terraform.tfvars.example  # plantilla de valores
```

## Requisitos previos

1. La imagen debe estar **publicada y pública** en Docker Hub
   (`rac4na/mod3_eva_final:1.0.0`), construida para `linux/amd64`.
2. Terraform >= 1.9 y Azure CLI instalados.
3. Sesión iniciada en Azure:
   ```bash
   az login
   az account set --subscription "<ID_DE_TU_SUSCRIPCION>"
   ```
4. Proveedores de recursos registrados (solo la primera vez por suscripción):
   ```bash
   az provider register --namespace Microsoft.App --wait
   az provider register --namespace Microsoft.OperationalInsights --wait
   ```

## Desplegar

```bash
cp terraform.tfvars.example terraform.tfvars   # y edita los valores
terraform init
terraform plan
terraform apply
```

Al terminar, Terraform imprime la URL pública:

```bash
curl "$(terraform output -raw hello_endpoint)"
```

## Destruir la infraestructura

Importante para no seguir consumiendo crédito de la suscripción:

```bash
terraform destroy
```

## Variables

| Variable | Por defecto | Descripción |
|---|---|---|
| `subscription_id` | `null` | Suscripción de Azure; si es null usa la sesión de `az login` |
| `location` | `eastus` | Región |
| `project_name` | `mod3-eva-final` | Prefijo de nombre de los recursos |
| `container_image` | `docker.io/rac4na/mod3_eva_final:1.0.0` | Imagen a desplegar |
| `greeting_name` | `Daybid` | Nombre que devuelve `/hello` |
| `container_port` | `8000` | Puerto de escucha dentro del contenedor |
| `cpu` / `memory` | `0.25` / `0.5Gi` | Recursos por réplica (proporción 1:2) |
| `min_replicas` | `1` | Poner `0` para escalar a cero sin tráfico |
| `max_replicas` | `3` | Tope de escalado horizontal |
| `tags` | ver `variables.tf` | Etiquetas aplicadas a todos los recursos |

## Relación con el pipeline de CI/CD

Terraform **crea** la infraestructura; el pipeline del repo `mod3_eva_final_app`
**actualiza la imagen** de la Container App en cada merge a `main` con
`az containerapp update`.

```
mod3_eva_final_infra   terraform apply        → crea la infra (manual, una vez)
mod3_eva_final_app     merge a main           → actualiza la imagen (automático)
```

Para que ambos convivan, `azurerm_container_app` lleva en [`main.tf`](main.tf):

```hcl
lifecycle {
  ignore_changes = [
    template[0].container[0].image,
  ]
}
```

Sin eso, Terraform vería el tag desplegado por el pipeline como una desviación y
el siguiente `apply` lo revertiría a `var.container_image`, deshaciendo el último
despliegue. Con el `ignore_changes`, `var.container_image` es solo la imagen con
la que nace la app y de ahí en adelante el tag lo manda el CD.

El resto de atributos (réplicas, CPU, memoria, probes, `GREETING_NAME`) sí sigue
gobernado por Terraform: cambiarlos aquí y hacer `apply` es lo correcto.

### Orden de operaciones

1. `terraform apply` en este repositorio.
2. Cargar los secrets en el repo `mod3_eva_final_app`.
3. Merge a `main` → el pipeline despliega.

Invertir 1 y 3 hace fallar el pipeline: no se puede actualizar una app que aún
no existe.

### Identidad que usa el pipeline

El despliegue no usa credenciales de larga vida. Hay una app registration
(`gh-mod3-eva-final`) con rol **Contributor** en la suscripción y una credencial
federada que solo acepta tokens de `refs/heads/main` de ese repositorio. Este
repositorio no necesita ningún secret configurado en GitHub: el `apply` se corre
en local con la sesión de `az login`.

Una vez creada la infraestructura se puede reducir el privilegio del service
principal del alcance de la suscripción al del resource group:

```bash
az role assignment create --assignee <client-id> --role Contributor \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-mod3-eva-final"
az role assignment delete --assignee <client-id> \
  --scope "/subscriptions/<sub-id>"
```

## Estado de Terraform

El estado se guarda **en local** (`terraform.tfstate`), excluido del control de
versiones porque almacena valores sensibles en claro. Para trabajo en equipo,
en `providers.tf` está preparado —comentado— un backend remoto en Azure Storage.

## Nota sobre imágenes privadas

La configuración asume un repositorio de Docker Hub **público**. Si la imagen
fuese privada, habría que añadir al `azurerm_container_app` un bloque `secret`
con el token del registro y un bloque `registry` que lo referencie.

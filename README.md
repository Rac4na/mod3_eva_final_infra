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
| `azurerm_key_vault` | Almacén del secreto que expone `/secreto` |
| `azurerm_key_vault_secret` | El secreto en sí |
| `azurerm_user_assigned_identity` | Identidad con la que la app lee el secreto |
| `azurerm_role_assignment` (×2) | Permisos de lectura (app) y escritura (Terraform) |

```
Resource Group  (rg-mod3-eva-final)
 ├── Log Analytics Workspace   (log-mod3-eva-final)
 ├── Key Vault                 (kv-mod3-eva-fin-<sufijo>)
 │    └── Secret               (secreto-demo)
 ├── User Assigned Identity    (id-mod3-eva-final)
 └── Container App Environment (cae-mod3-eva-final)
      └── Container App        (ca-mod3-eva-final)  → HTTPS público
```

## Estructura

```
.
├── .github/workflows/
│   └── terraform.yml         # validate → plan → apply
├── providers.tf              # versiones, backend remoto y provider azurerm
├── variables.tf              # parámetros de entrada
├── main.tf                   # resource group, environment y container app
├── keyvault.tf               # Key Vault, identidad y permisos
├── outputs.tf                # FQDN y URLs resultantes
├── .terraform.lock.hcl       # versiones exactas de los providers (versionado)
└── terraform.tfvars.example  # plantilla de valores
```

## El secreto y el Key Vault

La app expone en `/secreto` un valor guardado en Key Vault. Lo relevante es
**cómo llega hasta el contenedor**: la aplicación no habla con Key Vault ni
incluye el SDK de Azure. La plataforma resuelve el secreto y lo entrega como
variable de entorno.

```
Key Vault ── secreto-demo
    │
    │  la plataforma lo lee usando la identidad de la app
    ▼
Container App
    ├── secret { key_vault_secret_id, identity }
    └── env    { name = "SECRETO_DEMO", secret_name = ... }
              │
              ▼
        os.getenv("SECRETO_DEMO")   ← todo lo que hace la app
```

La ventaja no es solo tener menos código: el endpoint se puede probar en local
y en CI con un simple `-e SECRETO_DEMO=...`, sin necesidad de Azure ni de
mockear nada.

### Por qué una identidad *user assigned*

Es el detalle menos evidente del diseño. Con una identidad *system assigned*
—la que nace junto a la Container App— aparece una dependencia circular:
Terraform necesita el `principal_id` de la app para concederle el permiso, pero
la app necesita ese permiso ya concedido para resolver el secreto al arrancar.

Creando la identidad como recurso propio el orden queda lineal:

```
azurerm_user_assigned_identity  →  role assignment  →  azurerm_container_app
```

### Sobre el valor del secreto

`var.secret_value` tiene un valor de demostración escrito en `variables.tf`, y
este repositorio es público: **no es una credencial real y no debe usarse como
tal**. Para un secreto de verdad, las dos opciones son pasarlo por
`terraform.tfvars` (que está en `.gitignore`) o crearlo aparte:

```bash
az keyvault secret set --vault-name <vault> --name secreto-demo --value "..."
```

Conviene recordar también que exponer el valor de un secreto en un endpoint
público anula el propósito de un Key Vault. Aquí se hace porque el ejercicio lo
pide; en un sistema real el endpoint devolvería metadatos (que la lectura
funciona, el nombre, la versión) y nunca el valor.

## CI/CD de este repositorio

El pipeline está en
[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) y sigue el
mismo git-flow que el repo de la aplicación:

```
push a develop ──────► fmt + validate + plan            (CI)

PR develop → main ───► fmt + validate + plan            (CI)

merge a main ────────► fmt + validate + plan
                       └─ apply del plan guardado       (CD)
```

### El plan es el artefacto

Igual que en el repo de la app el artefacto es la imagen Docker, aquí es el
**plan**. El job `plan` genera `tfplan`, lo sube como artefacto, y el job
`apply` lo descarga y ejecuta `terraform apply tfplan`.

Se aplica el archivo y no la configuración a propósito: garantiza que lo que se
ejecuta es exactamente lo que se calculó y quedó registrado, sin margen a que
algo haya cambiado entre el plan y el apply.

El pipeline además emite un **warning visible** si el plan destruye recursos.
En infraestructura un `apply` no es como actualizar una imagen: puede borrar
cosas, y un `1 to destroy` es fácil que pase desapercibido entre las líneas de
un plan largo.

### Secrets requeridos

En `Settings → Secrets and variables → Actions`:

| Secret | |
|---|---|
| `AZURE_CLIENT_ID` | App registration `gh-mod3-eva-final` |
| `AZURE_TENANT_ID` | Tenant de Entra ID |
| `AZURE_SUBSCRIPTION_ID` | Suscripción de Azure |

Sin contraseñas: la autenticación es por OIDC federado, igual que en el repo de
la app. Terraform lo consume a través de `ARM_USE_OIDC` y las variables `ARM_*`
declaradas en el workflow.

Hay tres credenciales federadas registradas en Entra ID para este repositorio
(`refs/heads/main`, `refs/heads/develop` y `pull_request`). Las tres son
necesarias porque **incluso el `plan` requiere credenciales**: lee el estado
remoto y refresca los recursos existentes contra la API de Azure.

### Permisos del service principal

| Rol | Alcance | Por qué |
|---|---|---|
| `Contributor` | suscripción | Crear y modificar los recursos |
| `User Access Administrator` | suscripción | Crear los role assignments del Key Vault |
| `Storage Blob Data Contributor` | storage del estado | Leer y escribir el `tfstate` |

El segundo suele ser una sorpresa: **`Contributor` no puede crear role
assignments**. Como este código concede permisos sobre el Key Vault, sin ese rol
extra el pipeline falla con `AuthorizationFailed`.

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

Ninguno de los dos pipelines usa credenciales de larga vida contra Azure. Una
sola app registration (`gh-mod3-eva-final`) sirve a ambos repositorios, con una
credencial federada distinta por cada contexto de ejecución.

## Estado de Terraform

El estado vive **en Azure Storage**, no en local:

```
rg-tfstate
 └── sttfstate5fb84928
      └── tfstate (contenedor)
           └── mod3-eva-final.tfstate
```

Esto es un requisito del pipeline, no una preferencia. Un runner de GitHub
arranca sin nada: con estado local creería que la infraestructura no existe e
intentaría crearla de cero, fallando con *"A resource with the ID already
exists"*.

Tres decisiones sobre ese almacenamiento:

- **El storage account se crea fuera de Terraform** (con `az CLI`). Si lo
  gestionara este mismo código, el estado tendría que existir antes de poder
  crear el sitio donde se guarda.
- **`use_azuread_auth`** en lugar de la access key del storage account: el
  acceso se concede con el rol `Storage Blob Data Contributor`, así que no hay
  ninguna clave que guardar ni rotar.
- **Versionado de blobs activado**, para poder recuperar un estado anterior si
  uno se corrompe. El `tfstate` es el punto único de fallo de todo Terraform.

El estado sigue conteniendo valores sensibles en claro, y por eso el contenedor
no es público y `*.tfstate` continúa en `.gitignore`.

### Bloqueo de estado

El backend `azurerm` toma un lease sobre el blob mientras opera, de modo que dos
`apply` simultáneos no pueden corromper el estado: el segundo espera o falla con
un error de lock. Es la otra razón por la que el estado compartido importa en
cuanto hay un pipeline además de tu máquina.

## Nota sobre imágenes privadas

La configuración asume un repositorio de Docker Hub **público**. Si la imagen
fuese privada, habría que añadir al `azurerm_container_app` un bloque `secret`
con el token del registro y un bloque `registry` que lo referencie.

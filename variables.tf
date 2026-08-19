variable "subscription_id" {
  description = "ID de la suscripción de Azure. Si es null se usa ARM_SUBSCRIPTION_ID o la sesión de az login."
  type        = string
  default     = null
}

variable "location" {
  description = "Región de Azure donde se crean los recursos."
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Nombre base del proyecto. Solo minúsculas, números y guiones."
  type        = string
  default     = "mod3-eva-final"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name solo admite minúsculas, números y guiones (no guiones bajos)."
  }
}

variable "container_image" {
  description = "Imagen a desplegar, incluyendo registro y tag."
  type        = string
  default     = "docker.io/rac4na/mod3_eva_final:1.0.0"
}

variable "greeting_name" {
  description = "Nombre que devuelve el endpoint /hello."
  type        = string
  default     = "Daybid"
}

variable "container_port" {
  description = "Puerto en el que escucha la aplicación dentro del contenedor."
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "vCPU asignadas al contenedor."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Memoria asignada al contenedor. Debe guardar proporción 1:2 con cpu."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "Número mínimo de réplicas. Con 0 el servicio escala a cero cuando no hay tráfico."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Número máximo de réplicas."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Etiquetas aplicadas a todos los recursos."
  type        = map(string)
  default = {
    project     = "mod3-eva-final"
    environment = "dev"
    managed_by  = "terraform"
  }
}

variable "project_id" {
  type        = string
  description = "ID del proyecto de GCP"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Región de GCP"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "Zona de GCP"
}

variable "instance_name" {
  type        = string
  default     = "hola-vm"
  description = "Nombre de la instancia VM"
}

variable "machine_type" {
  type        = string
  default     = "e2-micro"
  description = "Tipo de máquina"
}

variable "ssh_user" {
  type        = string
  description = "Usuario SSH para la VM"
}

variable "ssh_public_key" {
  type        = string
  description = "Clave pública SSH"
}

variable "credentials_file" {
  type        = string
  description = "Ruta al archivo JSON de credenciales de la Service Account"
}

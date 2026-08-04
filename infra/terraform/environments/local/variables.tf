variable "namespace" {
  description = "Kubernetes namespace to deploy resources into"
  type        = string
  default     = "rube-goldberg"
}

variable "helm_postgresql_version" {
  description = "Pinned version for the Bitnami PostgreSQL Helm chart"
  type        = string
  default     = "18.8.6"
}

variable "helm_kafka_version" {
  description = "Pinned version for the Bitnami Kafka Helm chart"
  type        = string
  default     = "32.4.3"
}

variable "helm_redis_version" {
  description = "Pinned version for the Bitnami Redis Helm chart"
  type        = string
  default     = "27.0.18"
}

variable "helm_minio_version" {
  description = "Pinned version for the Bitnami MinIO Helm chart"
  type        = string
  default     = "17.0.21"
}

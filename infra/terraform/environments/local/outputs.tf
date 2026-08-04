output "namespace" {
  description = "Kubernetes namespace where resources are deployed"
  value       = kubernetes_namespace.rube_goldberg.metadata[0].name
}

output "postgresql_host" {
  description = "PostgreSQL service hostname"
  value       = "postgres.${kubernetes_namespace.rube_goldberg.metadata[0].name}.svc.cluster.local"
}

output "postgresql_port" {
  description = "PostgreSQL service port"
  value       = 5432
}

output "postgresql_username" {
  description = "PostgreSQL username"
  value       = "postgres"
}

output "kafka_bootstrap_server" {
  description = "Kafka bootstrap server address"
  value       = "kafka.${kubernetes_namespace.rube_goldberg.metadata[0].name}.svc.cluster.local:9092"
}

output "redis_host" {
  description = "Redis service hostname"
  value       = "redis.${kubernetes_namespace.rube_goldberg.metadata[0].name}.svc.cluster.local"
}

output "redis_port" {
  description = "Redis service port"
  value       = 6379
}

output "minio_endpoint" {
  description = "MinIO endpoint address"
  value       = "minio.${kubernetes_namespace.rube_goldberg.metadata[0].name}.svc.cluster.local"
}

output "minio_port" {
  description = "MinIO service port"
  value       = 9000
}

output "minio_bucket" {
  description = "Default MinIO artifacts bucket"
  value       = "rube-goldberg-artifacts"
}

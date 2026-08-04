terraform {
  backend "local" {}

  required_version = ">= 1.15.8"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.11.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.17.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

locals {
  namespace = var.namespace
  chart_dir = "${path.module}/../../../helm-charts"
}

# Namespace for all Rube Goldberg resources
resource "kubernetes_namespace" "rube_goldberg" {
  metadata {
    name = local.namespace
    labels = {
      app = "rube-goldberg"
    }
  }
}

# PostgreSQL credentials
resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "postgres-credentials"
    namespace = local.namespace
  }
  data = {
    username = "postgres"
    password = "PostgresPassw0rd!"
    database = "postgres"
  }
}

# Redis credentials
resource "kubernetes_secret" "redis_credentials" {
  metadata {
    name      = "redis-credentials"
    namespace = local.namespace
  }
  data = {
    password = "RedisPassw0rd!"
  }
}

# MinIO credentials
resource "kubernetes_secret" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = local.namespace
  }
  data = {
    root-user     = "minioadmin"
    root-password = "minioadmin"
  }
}

# PostgreSQL (Bitnami chart) - using local chart archive
resource "helm_release" "postgresql" {
  name      = "postgres"
  chart     = "${local.chart_dir}/postgresql-18.8.6.tgz"
  version   = var.helm_postgresql_version
  namespace = local.namespace

  set {
    name  = "auth.username"
    value = "postgres"
  }
  set {
    name  = "auth.password"
    value = "PostgresPassw0rd!"
  }
  set {
    name  = "auth.database"
    value = "postgres"
  }
  set {
    name  = "primary.persistence.enabled"
    value = "true"
  }
  set {
    name  = "primary.persistence.size"
    value = "2Gi"
  }
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "256Mi"
  }
}

# Kafka KRaft (Bitnami chart) - using local chart archive
resource "helm_release" "kafka" {
  name      = "kafka"
  chart     = "${local.chart_dir}/kafka-32.4.3.tgz"
  version   = var.helm_kafka_version
  namespace = local.namespace
  timeout   = 300

  set {
    name  = "global.security.allowInsecureImages"
    value = "true"
  }
  set {
    name  = "image.registry"
    value = "registry-1.docker.io"
  }
  set {
    name  = "image.repository"
    value = "bitnamilegacy/kafka"
  }
  set {
    name  = "replica.replicaCount"
    value = "1"
  }
  set {
    name  = "zookeeper.enabled"
    value = "false"
  }
  set {
    name  = "listeners.client.protocol"
    value = "PLAINTEXT"
  }
  set {
    name  = "listeners.controller.protocol"
    value = "PLAINTEXT"
  }
  set {
    name  = "listeners.interbroker.protocol"
    value = "PLAINTEXT"
  }
  set {
    name  = "service.ports.client"
    value = "9092"
  }
  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "256Mi"
  }
  set {
    name  = "probeStartupFailureThreshold"
    value = "60"
  }
}

# Redis (Bitnami chart) - using local chart archive
resource "helm_release" "redis" {
  name      = "redis"
  chart     = "${local.chart_dir}/redis-27.0.18.tgz"
  version   = var.helm_redis_version
  namespace = local.namespace

  set {
    name  = "auth.password"
    value = "RedisPassw0rd!"
  }
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "master.persistence.enabled"
    value = "true"
  }
  set {
    name  = "master.persistence.size"
    value = "2Gi"
  }
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "256Mi"
  }
}

# MinIO (Bitnami chart) - using local chart archive
resource "helm_release" "minio" {
  name      = "minio"
  chart     = "${local.chart_dir}/minio-17.0.21.tgz"
  version   = var.helm_minio_version
  namespace = local.namespace

  set {
    name  = "global.security.allowInsecureImages"
    value = "true"
  }
  set {
    name  = "image.registry"
    value = "registry-1.docker.io"
  }
  set {
    name  = "image.repository"
    value = "bitnamilegacy/minio"
  }
  set {
    name  = "console.image.registry"
    value = "registry-1.docker.io"
  }
  set {
    name  = "console.image.repository"
    value = "bitnamilegacy/minio-object-browser"
  }
  set {
    name  = "auth.existingSecret"
    value = "minio-credentials"
  }
  set {
    name  = "mode"
    value = "standalone"
  }
  set {
    name  = "persistence.enabled"
    value = "true"
  }
  set {
    name  = "persistence.size"
    value = "2Gi"
  }
  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "defaultBuckets"
    value = "rube-goldberg-artifacts:none"
  }
}

terraform {
  backend "local" {}

  required_version = ">= 1.15.8"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
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

  set = [
    {
      name  = "auth.username"
      value = "postgres"
    },
    {
      name  = "auth.password"
      value = "PostgresPassw0rd!"
    },
    {
      name  = "auth.database"
      value = "postgres"
    },
    {
      name  = "primary.persistence.enabled"
      value = "true"
    },
    {
      name  = "primary.persistence.size"
      value = "2Gi"
    },
    {
      name  = "architecture"
      value = "standalone"
    },
    {
      name  = "service.type"
      value = "ClusterIP"
    },
    {
      name  = "resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "resources.requests.cpu"
      value = "256Mi"
    },
  ]
}

# Kafka KRaft (Bitnami chart) - using local chart archive
resource "helm_release" "kafka" {
  name      = "kafka"
  chart     = "${local.chart_dir}/kafka-32.4.3.tgz"
  version   = var.helm_kafka_version
  namespace = local.namespace
  timeout   = 300

  set = [
    {
      name  = "global.security.allowInsecureImages"
      value = "true"
    },
    {
      name  = "image.registry"
      value = "registry-1.docker.io"
    },
    {
      name  = "image.repository"
      value = "bitnamilegacy/kafka"
    },
    {
      name  = "replica.replicaCount"
      value = "1"
    },
    {
      name  = "zookeeper.enabled"
      value = "false"
    },
    {
      name  = "listeners.client.protocol"
      value = "PLAINTEXT"
    },
    {
      name  = "listeners.controller.protocol"
      value = "PLAINTEXT"
    },
    {
      name  = "listeners.interbroker.protocol"
      value = "PLAINTEXT"
    },
    {
      name  = "service.ports.client"
      value = "9092"
    },
    {
      name  = "resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "resources.requests.cpu"
      value = "256Mi"
    },
    {
      name  = "probeStartupFailureThreshold"
      value = "60"
    },
  ]
}

# Redis (Bitnami chart) - using local chart archive
resource "helm_release" "redis" {
  name      = "redis"
  chart     = "${local.chart_dir}/redis-27.0.18.tgz"
  version   = var.helm_redis_version
  namespace = local.namespace

  set = [
    {
      name  = "auth.password"
      value = "RedisPassw0rd!"
    },
    {
      name  = "architecture"
      value = "standalone"
    },
    {
      name  = "master.persistence.enabled"
      value = "true"
    },
    {
      name  = "master.persistence.size"
      value = "2Gi"
    },
    {
      name  = "service.type"
      value = "ClusterIP"
    },
    {
      name  = "resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "resources.requests.cpu"
      value = "256Mi"
    },
  ]
}

# MinIO (Bitnami chart) - using local chart archive
resource "helm_release" "minio" {
  name      = "minio"
  chart     = "${local.chart_dir}/minio-17.0.21.tgz"
  version   = var.helm_minio_version
  namespace = local.namespace

  set = [
    {
      name  = "global.security.allowInsecureImages"
      value = "true"
    },
    {
      name  = "image.registry"
      value = "registry-1.docker.io"
    },
    {
      name  = "image.repository"
      value = "bitnamilegacy/minio"
    },
    {
      name  = "console.image.registry"
      value = "registry-1.docker.io"
    },
    {
      name  = "console.image.repository"
      value = "bitnamilegacy/minio-object-browser"
    },
    {
      name  = "auth.existingSecret"
      value = "minio-credentials"
    },
    {
      name  = "mode"
      value = "standalone"
    },
    {
      name  = "persistence.enabled"
      value = "true"
    },
    {
      name  = "persistence.size"
      value = "2Gi"
    },
    {
      name  = "service.type"
      value = "ClusterIP"
    },
    {
      name  = "resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "defaultBuckets"
      value = "rube-goldberg-artifacts:none"
    },
  ]
}

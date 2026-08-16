terraform {
  backend "local" {}

  required_version = "1.15.8"
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

# Generated, never-committed credentials. Terraform stores these in state only.
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "random_password" "minio_user" {
  length  = 16
  special = false
  upper   = false
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

# PostgreSQL credentials (password sourced from random_password)
resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "postgres-credentials"
    namespace = local.namespace
  }
  data = {
    username          = "postgres"
    password          = random_password.postgres.result
    postgres-password = random_password.postgres.result
    database          = "postgres"
  }
}

# Redis credentials (password sourced from random_password)
resource "kubernetes_secret" "redis_credentials" {
  metadata {
    name      = "redis-credentials"
    namespace = local.namespace
  }
  data = {
    redis-password = random_password.redis.result
  }
}

# MinIO credentials (password sourced from random_password; root-user is the default username)
resource "kubernetes_secret" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = local.namespace
  }
  data = {
    root-user     = random_password.minio_user.result
    root-password = random_password.minio.result
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
      name  = "auth.existingSecret"
      value = "postgres-credentials"
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
      name  = "primary.resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "primary.resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "primary.resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "primary.resources.requests.cpu"
      value = "250m"
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
    # Keep the local KRaft deployment to one broker/controller; the chart
    # defaults to three controllers, which exceeds the laptop memory budget.
    {
      name  = "controller.replicaCount"
      value = "1"
    },
    # Internal Kafka topics must also fit the single-broker local cluster.
    {
      name  = "overrideConfiguration.offsets\\.topic\\.replication\\.factor"
      value = "1"
    },
    {
      name  = "overrideConfiguration.transaction\\.state\\.log\\.replication\\.factor"
      value = "1"
    },
    {
      name  = "overrideConfiguration.transaction\\.state\\.log\\.min\\.isr"
      value = "1"
    },
    {
      name  = "overrideConfiguration.share\\.coordinator\\.state\\.topic\\.replication\\.factor"
      value = "1"
    },
    {
      name  = "overrideConfiguration.share\\.coordinator\\.state\\.topic\\.min\\.isr"
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
      name  = "controller.resources.limits.memory"
      value = "1Gi"
    },
    {
      name  = "controller.resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "512Mi"
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "250m"
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
      name  = "auth.existingSecret"
      value = "redis-credentials"
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
      name  = "master.resources.limits.memory"
      value = "192Mi"
    },
    {
      name  = "master.resources.limits.cpu"
      value = "250m"
    },
    {
      name  = "master.resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "master.resources.requests.cpu"
      value = "100m"
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
      value = "384Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "resources.requests.memory"
      value = "128Mi"
    },
    {
      name  = "resources.requests.cpu"
      value = "250m"
    },
    {
      name  = "defaultBuckets"
      value = "rube-goldberg-artifacts:none"
    },
  ]
}

# Egress-restricted NetworkPolicies (managed here so they track the namespace
# lifecycle). The manifest file lives under infra/k8s/network-policies.yaml.
data "kubectl_path_documents" "network_policies" {
  pattern = "${path.module}/../../../infra/k8s/network-policies.yaml"
}

resource "kubectl_manifest" "network_policies" {
  for_each  = toset(data.kubectl_path_documents.network_policies.documents)
  yaml_body = each.value

  depends_on = [kubernetes_namespace.rube_goldberg]
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

variable "YC_TOKEN" {
  type        = string
  description = "Yandex Cloud OAuth token"
  sensitive   = true
}

variable "YC_CLOUD_ID" {
  type        = string
  sensitive   = true
}

variable "YC_FOLDER_ID" {
  type        = string
  sensitive   = true
}

variable "CI_PROJECT_DIR" {
  description = "GitLab CI project directory"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init"
  type        = string
}

variable "k8s_sa_id" {
  description = "ID of existing Kubernetes service account with roles"
  type        = string
}

provider "yandex" {
  token     = var.YC_TOKEN
  cloud_id  = var.YC_CLOUD_ID
  folder_id = var.YC_FOLDER_ID
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "network" {
  name = "debian-vm-network"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "debian-vm-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.11.0/24"]
}

resource "yandex_vpc_address" "external_ip" {
  name = "debian-vm-external-ip"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_compute_instance" "debian-vm" {
  name        = "debian-vm"
  zone        = "ru-central1-a"
  platform_id = "standard-v1"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd89p1qjq2vedvn83uj9"
      size     = 20
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
    nat_ip_address = yandex_vpc_address.external_ip.external_ipv4_address[0].address
  }

  metadata = {
    user-data = file("${var.CI_PROJECT_DIR}/deploy/terraform/cloud_init.txt")
  }
}

resource "yandex_lb_target_group" "vm_target_group" {
  name = "debian-vm-target-group"

  target {
    subnet_id  = yandex_vpc_subnet.subnet.id
    address    = yandex_compute_instance.debian-vm.network_interface[0].ip_address
  }
}

resource "yandex_lb_network_load_balancer" "vm_load_balancer" {
  name = "debian-vm-load-balancer"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.vm_target_group.id
    healthcheck {
      name = "http-healthcheck"
      http_options {
        port = 80
        path = "/"
      }
    }
  }

  depends_on = [
    yandex_compute_instance.debian-vm,
    yandex_vpc_subnet.subnet
  ]
}

output "external_ip" {
  value = yandex_vpc_address.external_ip.external_ipv4_address[0].address
}

output "load_balancer_ip" {
  value = [for listener in yandex_lb_network_load_balancer.vm_load_balancer.listener : tolist(listener.external_address_spec)[0].address if listener.name == "http-listener"][0]
}

resource "yandex_kubernetes_cluster" "k8s_cluster" {
  name        = "demo-k8s-cluster"
  network_id  = yandex_vpc_network.network.id

  master {
  zonal {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.subnet.id
  }

    public_ip = true
  }

  service_account_id      = var.k8s_sa_id
  node_service_account_id = var.k8s_sa_id
}

resource "yandex_kubernetes_node_group" "k8s_nodes" {
  cluster_id = yandex_kubernetes_cluster.k8s_cluster.id
  name       = "demo-k8s-nodes"
  version    = "1.29"

  instance_template {
    platform_id = "standard-v1"

    resources {
      cores  = 2
      memory = 4
    }

    boot_disk {
      type = "network-ssd"
      size = 30
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.subnet.id]
      nat        = true
    }

    metadata = {
      user-data = file("${var.CI_PROJECT_DIR}/deploy/terraform/cloud_init.txt")
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }
}

resource "yandex_container_registry" "registry" {
  name = "easy-app-registry"
}

output "registry_id" {
  value = yandex_container_registry.registry.id
}

output "registry_url" {
  value = "cr.yandex/${yandex_container_registry.registry.id}"

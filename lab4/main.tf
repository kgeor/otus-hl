terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.TOKEN
  cloud_id  = var.CLOUD_ID
  folder_id = var.FOLDER_ID
  zone      = var.zone
}

locals {
  vm = {
    "nginx-lb-1" = { role = "nginx_lb", cpu = 2, ram = 2, disk = 16 },
    "nginx-lb-2" = { role = "nginx_lb", cpu = 2, ram = 2, disk = 16 },
    "db-1"       = { role = "db", cpu = 2, ram = 4, disk = 16 },
    "backend-1"  = { role = "backend", cpu = 2, ram = 4, disk = 16, sec_net = true },
    "backend-2"  = { role = "backend", cpu = 2, ram = 4, disk = 16, sec_net = true },
    "backend-3"  = { role = "backend", cpu = 2, ram = 4, disk = 16, sec_net = true },
    "storage-1"  = { role = "storage", cpu = 2, ram = 2, disk = 16, sec_net = true, sec_disk = 16 }
  }
}

data "yandex_compute_image" "image" {
  family = var.image_family
}

data "template_file" "cloud-init" {
  template = file("${path.module}/cloudinit.yml.tpl")
  vars = {
    ssh_key = file("${var.ssh_key}.pub")
    user    = var.user
  }
}

resource "yandex_vpc_network" "net" {
  name = "localnet-lab4"
}

resource "yandex_vpc_subnet" "subnet1" {
  name           = "subnet-1"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = var.subnet_cidr
}

resource "yandex_vpc_subnet" "subnet2" {
  name           = "subnet-2"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = var.subnet2_cidr
}

resource "yandex_vpc_security_group" "nginx-rp" {
  name        = "nginx_sec_group"
  description = "My security group for NGINX reverse-proxy"
  network_id  = yandex_vpc_network.net.id

  # labels = {
  #   my-label = "my-label-value"
  # }

  dynamic "ingress" {
    for_each = toset([22, 80])
    content {
      protocol       = "TCP"
      description    = "allow inbound"
      v4_cidr_blocks = ["0.0.0.0/0"]
      port           = ingress.value
    }
  }
  ingress {
    protocol       = "ANY"
    description    = "allow all localnet"
    v4_cidr_blocks = var.subnet_cidr
    port           = -1
  }

  egress {
    protocol       = "ANY"
    description    = "allow any outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = -1
  }
}

resource "yandex_vpc_security_group" "internal" {
  name        = "internal-sec-group"
  description = "My security group for backend nodes"
  network_id  = yandex_vpc_network.net.id


  dynamic "ingress" {
    for_each = toset([22])
    content {
      protocol       = "TCP"
      description    = "allow ssh inbound"
      v4_cidr_blocks = ["0.0.0.0/0"]
      port           = ingress.value
    }
  }

  ingress {
    protocol       = "ANY"
    description    = "allow all from lan"
    v4_cidr_blocks = var.subnet_cidr
    port           = -1
  }

  egress {
    protocol       = "ANY"
    description    = "allow any outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = -1
  }
}

resource "yandex_compute_disk" "storage-disk" {
  for_each = {
    for instance, params in local.vm : instance => params["sec_disk"]
  if lookup(params, "sec_disk", null) != null }
  name = "storage-disk-${each.key}"
  type = "network-hdd"
  zone = var.zone
  size = each.value
  labels = {
    vm = each.key
  }
}

resource "yandex_compute_instance" "vm" {
  for_each    = local.vm
  name        = each.key
  hostname    = each.key
  platform_id = "standard-v3"
  zone        = var.zone
  labels = {
    ansible_group = each.value["role"]
    storage       = lookup(each.value, "sec_disk", null) != null ? true : false
  }
  allow_stopping_for_update = true


  resources {
    cores         = each.value["cpu"]
    memory        = each.value["ram"]
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      name     = "boot-disk-${each.key}"
      type     = "network-hdd"
      size     = each.value["disk"]
      image_id = data.yandex_compute_image.image.id
    }
  }

  dynamic "secondary_disk" {
    for_each = [
      for disk in yandex_compute_disk.storage-disk : disk.id
      if disk.labels.vm == each.key
    ]
    content {
      disk_id     = secondary_disk.value
      auto_delete = true
    }
  }

  network_interface {
    index              = 0
    subnet_id          = yandex_vpc_subnet.subnet1.id
    security_group_ids = (each.value["role"] == "nginx_lb" ? [yandex_vpc_security_group.nginx-rp.id] : [yandex_vpc_security_group.internal.id])
    nat                = true
  }

  dynamic "network_interface" {
    for_each = {
      for instance, params in local.vm : instance => params["sec_net"]
      if lookup(params, "sec_net", null) != null && instance == each.key
    }
    content {
      index     = 1
      subnet_id = yandex_vpc_subnet.subnet2.id
      # security_group_ids = (each.value["role"] == "nginx_lb" ? [yandex_vpc_security_group.nginx-rp.id] : [yandex_vpc_security_group.internal.id])
      nat = false
    }
  }

  metadata = {
    user-data = data.template_file.cloud-init.rendered
  }

  provisioner "remote-exec" {
    inline = ["cat /etc/hostname"]

    connection {
      type        = "ssh"
      user        = var.user
      host        = self.network_interface.0.nat_ip_address
      private_key = file(var.ssh_key)
    }
  }
}

resource "yandex_lb_target_group" "web-tg" {
  #folder_id = local.folder_id
  name      = "ingress-tg"
  region_id = "ru-central1"

  dynamic "target" {
    for_each = {
      for node, params in local.vm : node => params
      if lookup(params, "role", null) == "nginx_lb"
    }
    content {
      address   = yandex_compute_instance.vm["${target.key}"].network_interface.0.ip_address
      subnet_id = yandex_vpc_subnet.subnet1.id
    }
  }
}

resource "yandex_vpc_address" "lb_external_ip" {
  name = "cluster_external_ip"
  # folder_id = local.folder_id
  external_ipv4_address {
    zone_id = var.zone
  }
}

resource "yandex_lb_network_load_balancer" "cluster_lb" {
  # folder_id = local.folder_id
  name = "cluster-lb"
  # type      = "internal"

  listener {
    name        = "http-listener"
    port        = 80
    target_port = 80
    # internal_address_spec {
    #   subnet_id = module.nat.private_subnet.subnet_id
    # }
    external_address_spec {
      ip_version = "ipv4"
      address    = yandex_vpc_address.lb_external_ip.external_ipv4_address[0].address
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.web-tg.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/wp-admin/install.php"
      }
    }
  }
}

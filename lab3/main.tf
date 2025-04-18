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

data "yandex_compute_image" "image" {
  family = var.image_family
}

data "template_file" "cloud-init" {
  template = file("${path.module}/cloudinit.yml.tpl")
  vars = {
    ssh_key = file("${var.ssh_key}.pub")
    user = var.user
  }
}

resource "yandex_vpc_network" "net" {
  #name = "localnet"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "subnet-103"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = var.subnet_cidr
}

resource "yandex_vpc_security_group" "nginx_rp" {
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
  name        = "internal_sec_group"
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

resource "yandex_compute_instance" "vm" {
  #for_each= toset(["web", "db", "wp-1", "wp-2"])
  for_each = tomap({ 
    "nginx-lb" = { role = "nginx_lb" },
    "db-1" = { role = "db" },
    "wp-1" = { role = "nginx_wp" },
    "wp-2" = { role = "nginx_wp" },
  })
  name        = each.key
  hostname    = each.key
  platform_id = "standard-v3"
  zone        = var.zone
  labels = {
    ansible_group = each.value["role"]
  }

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      name = "boot-disk-${each.key}"
      type = "network-hdd"
      size     = "20"
      image_id = data.yandex_compute_image.image.id
    }
  }

  network_interface {
    # index = 1
    subnet_id          = yandex_vpc_subnet.subnet.id
    security_group_ids = (each.value["role"] == "nginx_lb" ? [yandex_vpc_security_group.nginx_rp.id] : [yandex_vpc_security_group.internal.id])
    nat                = true
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

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
    user    = var.user
  }
}

resource "yandex_vpc_network" "net" {
  #name = "localnet"
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


resource "yandex_vpc_security_group" "node_group" {
  name        = "node_sec_group"
  description = "My security group for linux"
  network_id  = yandex_vpc_network.net.id
  # labels = {
  #   my-label = "my-label-value"
  # }

  dynamic "ingress" {
    for_each = [22]
    content {
      protocol       = "TCP"
      description    = "allow ssh inbound"
      v4_cidr_blocks = ["0.0.0.0/0"]
      port           = ingress.value
    }
  }

  ingress {
    protocol       = "ANY"
    description    = "allow all localnet"
    v4_cidr_blocks = concat(var.subnet_cidr, var.subnet2_cidr)
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
  name = "storage-disk"
  type = "network-hdd"
  zone = var.zone
  size = "5"
}


resource "yandex_compute_instance" "gfs-node" {
  count                     = 3
  name                      = "gfs-node-${count.index + 1}"
  hostname                  = "gfs-node-${count.index + 1}"
  platform_id               = "standard-v3"
  zone                      = var.zone
  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      name = "boot-disk-gfs-${count.index + 1}"
      type = "network-hdd"
      #zone = var.zone
      size     = "20"
      image_id = data.yandex_compute_image.image.id
    }
  }

  network_interface {
    index              = 0
    subnet_id          = yandex_vpc_subnet.subnet1.id
    security_group_ids = [yandex_vpc_security_group.node_group.id]
    nat                = true
  }

  network_interface {
    index     = 1
    subnet_id = yandex_vpc_subnet.subnet2.id
    #security_group_ids = [yandex_vpc_security_group.node_group.id]
    nat = false
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

resource "yandex_compute_instance" "iscsi-storage" {
  count                     = 1
  name                      = "iscsi-${count.index + 1}"
  hostname                  = "iscsi-${count.index + 1}"
  platform_id               = "standard-v3"
  zone                      = var.zone
  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      name = "boot-disk-iscsi-${count.index + 1}"
      type = "network-hdd"
      #zone = var.zone
      size     = "20"
      image_id = data.yandex_compute_image.image.id
    }
  }

  secondary_disk {
    disk_id     = yandex_compute_disk.storage-disk.id
    auto_delete = true
  }

  network_interface {
    index              = 0
    subnet_id          = yandex_vpc_subnet.subnet1.id
    security_group_ids = [yandex_vpc_security_group.node_group.id]
    nat                = true
  }

  network_interface {
    index     = 1
    subnet_id = yandex_vpc_subnet.subnet2.id
    #security_group_ids = [yandex_vpc_security_group.node_group.id]
    nat = false
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
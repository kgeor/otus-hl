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

resource "yandex_vpc_network" "net" {
  name = "localnet"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "subnet103"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.3.0.0/24"]
}

resource "yandex_vpc_security_group" "fw_group" {
  name        = "nginx_sec_group"
  description = "My security group"
  network_id  = yandex_vpc_network.net.id

  # labels = {
  #   my-label = "my-label-value"
  # }

  ingress {
    protocol       = "TCP"
    description    = "allow ssh inbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "allow http inbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "allow any outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = -1
  }
}

resource "yandex_compute_disk" "boot-disk" {
  name     = "boot-disk"
  type     = "network-hdd"
  zone     = var.zone
  size     = "20"
  image_id = data.yandex_compute_image.image.id
}

resource "yandex_compute_instance" "vm" {
  name        = "lab1-nginx"
  hostname    = "lab1-nginx"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk.id
  }

  network_interface {
    # index = 1
    subnet_id          = yandex_vpc_subnet.subnet.id
    security_group_ids = [yandex_vpc_security_group.fw_group.id]
    nat                = true
  }

  metadata = {
    #user-data = "#cloud-config\nusers:\n - name: devops\n groups: sudo\n shell: /bin/bash\n sudo: 'ALL=(ALL) NOPASSWD:ALL'\n ssh-authorized-keys:\n - ${file("~/.ssh/id_rsa.pub")}"
    ssh-keys = "${var.user}:${file("${var.ssh_key}.pub")}"
  }

  provisioner "remote-exec" {
    inline = ["cat /etc/*release"]

    connection {
      type        = "ssh"
      user        = var.user
      host        = self.network_interface.0.nat_ip_address
      private_key = file(var.ssh_key)
    }
  }
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_FORCE_COLOR       = "True"
    }
    command = "ansible-playbook -u ${var.user} -i '${self.network_interface.0.nat_ip_address},' --private-key ${var.ssh_key} ./ansible/playbook.yml"
  }
}

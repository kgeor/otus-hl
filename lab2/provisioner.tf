resource "local_file" "ansible_inventory" {
  #depends_on = [resource.yandex_compute_instance.linux-vm]
  content = templatefile("./ansible/inventory.tpl", {
    ip_node    = { for node in yandex_compute_instance.gfs-node : node.hostname => node.network_interface.0.nat_ip_address }
    ip_storage = { for node in yandex_compute_instance.iscsi-storage : node.hostname => node.network_interface.0.nat_ip_address }
    user       = var.user
  })
  filename = "./ansible/inventory.ini"
}

resource "null_resource" "ansible_provision" {
  depends_on = [local_file.ansible_inventory]
  triggers = {
    file_changed = md5(local_file.ansible_inventory.content)
  }
  provisioner "local-exec" {
    command = "ansible-playbook -i ./ansible/inventory.ini --private-key ${var.ssh_key} ./ansible/playbook.yml"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_FORCE_COLOR       = "True"
    }
    #interpreter = ["bash", "--color=auto", "-c"]
  }

}
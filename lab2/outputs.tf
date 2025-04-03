output "gfs_ip_address" {
  value = { for vm in yandex_compute_instance.gfs-node :
    vm.hostname => ["public_IP = ${vm.network_interface.0.nat_ip_address}, private_IP = ${vm.network_interface.0.ip_address}",
    "public_IP = ${vm.network_interface.1.nat_ip_address}, private_IP = ${vm.network_interface.1.ip_address}"]
    #yandex_compute_instance.linux-vm.*.network_interface.0.nat_ip_address
  }
}
output "iscsi_ip_address" {
  value = { for vm in yandex_compute_instance.iscsi-storage :
    vm.hostname => ["public_IP = ${vm.network_interface.0.nat_ip_address}, private_IP = ${vm.network_interface.0.ip_address}",
    "public_IP = ${vm.network_interface.1.nat_ip_address}, private_IP = ${vm.network_interface.1.ip_address}"]
    #yandex_compute_instance.linux-vm.*.network_interface.0.nat_ip_address
  }
}
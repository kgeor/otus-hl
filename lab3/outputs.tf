output "vm_ip_addresses" {
  value = { for vm in yandex_compute_instance.vm :
     vm.hostname => ["public_IP = ${vm.network_interface.0.nat_ip_address}, private_IP = ${vm.network_interface.0.ip_address}"]
  }
}

output "site_address" {
  value = "http://${yandex_compute_instance.vm["nginx-lb"].network_interface.0.nat_ip_address}"
}

output "vm_ip_addresses" {
  value = { for vm in yandex_compute_instance.vm :
    vm.hostname => ["public_IP = ${vm.network_interface.0.nat_ip_address}, private_IP = ${vm.network_interface.0.ip_address}"]
  }
}

output "site_address" {
  value = "http://${yandex_vpc_address.lb_external_ip.external_ipv4_address[0].address}"
}

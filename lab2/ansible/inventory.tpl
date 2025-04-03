[cloud_vm:children]
gfs_node
iscsi_storage
[cloud_vm:vars]
ansible_user=${ user }

[gfs_node]
%{ for hostname, addr in ip_node ~}
${ hostname } ansible_host=${ addr }
%{ endfor ~}

[iscsi_storage]
%{ for hostname, addr in ip_storage ~}
${ hostname } ansible_host=${ addr }
%{ endfor ~}

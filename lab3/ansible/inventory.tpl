%{ for group in groups ~}
[${ group }]
%{ for host, param in nodes ~}
%{ if param["group"] == group ~}
${ host } ansible_host=${ param["addr"] } ansible_user=${ user }
%{ endif ~}
%{ endfor ~}
%{ endfor ~}
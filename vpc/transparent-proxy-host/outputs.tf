# Outputs
output "proxy_public_ip" {
  value = aws_instance.proxy.public_ip
}

output "proxy_cert_path" {
  value = time_sleep.transparent_proxy_resources_wait.triggers["proxy_cert_path"]
}

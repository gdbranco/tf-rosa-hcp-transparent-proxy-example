resource "tls_private_key" "proxy_pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "proxy_ssh_key" {
  key_name   = "${var.prefix}-proxy-ssh-key"
  public_key = tls_private_key.proxy_pk.public_key_openssh
}

resource "local_file" "proxy_private_ssh_key" {
  filename        = "${aws_key_pair.proxy_ssh_key.key_name}.pem"
  content         = tls_private_key.proxy_pk.private_key_pem
  file_permission = 0400
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

resource "aws_security_group" "proxy_host_ingress" {
  name   = "${var.prefix}-proxy-security-group"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(["${chomp(data.http.myip.response_body)}/32"], var.cidr_blocks == null ? [] : var.cidr_blocks)
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

data "aws_ami" "rhel9" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true

  filter {
    name   = "platform-details"
    values = ["Red Hat Enterprise Linux"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "manifest-location"
    values = ["amazon/RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP2"]
  }

  owners = ["309956199498"] # Amazon's "Official Red Hat" account
}

resource "aws_instance" "proxy" {
  ami                         = var.ami_id != null ? var.ami_id : data.aws_ami.rhel9[0].id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.proxy_ssh_key.key_name
  vpc_security_group_ids      = [aws_security_group.proxy_host_ingress.id]
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  source_dest_check           = false
  user_data                   = var.user_data_file != null ? var.user_data_file : file("${path.module}/../../assets/transparent-proxy-host-user-data.sh")
  user_data_replace_on_change = true
  tags = {
    Name = "${var.prefix}-proxy-host"
  }
}

data "aws_region" "current" {}
resource "time_sleep" "proxy_host_resources_wait" {
  create_duration = "30s"
  depends_on      = [aws_instance.proxy]
}

locals {
  ec2_host        = "ec2-${replace(aws_instance.proxy.public_ip, ".", "-")}.${data.aws_region.current.name}.compute.amazonaws.com"
  ec2_username    = var.ami_username != null ? var.ami_username : "ec2-user"
  proxy_cert_path = "squid-${aws_instance.proxy.id}.crt"
}
resource "null_resource" "copy_proxy_cert_local" {
  triggers = {
    proxy_cert_path = local.proxy_cert_path
  }

  provisioner "local-exec" {
    command = <<-EOF
      ssh-keyscan -H ${local.ec2_host} >> ~/.ssh/known_hosts
      scp -i ${local_file.proxy_private_ssh_key.filename} ${local.ec2_username}@${local.ec2_host}:/home/${local.ec2_username}/squid.crt ${self.triggers.proxy_cert_path}
    EOF
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      rm ${self.triggers.proxy_cert_path}
    EOF
  }
  depends_on = [time_sleep.proxy_host_resources_wait]
}

data "local_file" "proxy_cert" {
  filename   = local.proxy_cert_path
  depends_on = [null_resource.copy_proxy_cert_local]
}

resource "time_sleep" "transparent_proxy_resources_wait" {
  create_duration  = "30s"
  destroy_duration = "30s"
  triggers = {
    proxy_cert_path = data.local_file.proxy_cert.filename
  }
  depends_on = [data.local_file.proxy_cert]
}

resource "aws_route" "proxy_route" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.proxy.primary_network_interface_id
}

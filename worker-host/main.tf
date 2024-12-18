###
# Worker
###
resource "tls_private_key" "worker_pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "worker_ssh_key" {
  key_name   = "${var.prefix}-worker-ssh-key"
  public_key = tls_private_key.worker_pk.public_key_openssh
}

resource "local_file" "worker_private_ssh_key" {
  filename        = "${aws_key_pair.worker_ssh_key.key_name}.pem"
  content         = tls_private_key.worker_pk.private_key_pem
  file_permission = 0400
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

resource "aws_security_group" "worker_host_ingress" {
  name   = "${var.prefix}-worker-security-group"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
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

resource "aws_instance" "worker" {
  ami                    = var.ami_id != null ? var.ami_id : data.aws_ami.rhel9[0].id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.worker_ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.worker_host_ingress.id]
  subnet_id              = var.subnet_id

  tags = {
    Name = "${var.prefix}-worker-host"
  }
}

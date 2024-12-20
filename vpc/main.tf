locals {
  tags               = var.tags == null ? {} : var.tags
  availability_zones = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.availability_zones_count)
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(
    {
      "Name" = "${var.name_prefix}-vpc"
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "public_subnet" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, length(local.availability_zones) * 2, count.index)
  availability_zone = local.availability_zones[count.index]
  tags = merge(
    {
      "Name"                   = join("-", [var.name_prefix, "subnet", "public${count.index + 1}", local.availability_zones[count.index]])
      "kubernetes.io/role/elb" = ""
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "private_subnet" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, length(local.availability_zones) * 2, count.index + length(local.availability_zones))
  availability_zone = local.availability_zones[count.index]
  tags = merge(
    {
      "Name"                            = join("-", [var.name_prefix, "subnet", "private${count.index + 1}", local.availability_zones[count.index]])
      "kubernetes.io/role/internal-elb" = ""
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

#
# Internet gateway
#
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = merge(
    {
      "Name" = "${var.name_prefix}-igw"
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

#
# Route tables
#
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  tags = merge(
    {
      "Name" = "${var.name_prefix}-public"
    },
    local.tags,
  )
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.internet_gateway.id
  }
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table" "private_route_table" {
  count = length(local.availability_zones)

  vpc_id = aws_vpc.vpc.id
  tags = merge(
    {
      "Name" = join("-", [var.name_prefix, "rtb", "private${count.index}", local.availability_zones[count.index]])
    },
    local.tags,
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
}

# Private route for vpc endpoint
resource "aws_vpc_endpoint_route_table_association" "private_vpc_endpoint_route_table_association" {
  count = length(local.availability_zones)

  route_table_id  = aws_route_table.private_route_table[count.index].id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

#
# Route table associations
#
resource "aws_route_table_association" "public_route_table_association" {
  count = length(local.availability_zones)

  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(local.availability_zones)

  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id
}

#########################
# Transparent Proxy Host
#########################
module "transparent-proxy" {
  count  = var.enable_transparent_proxy ? 1 : 0
  source = "./transparent-proxy-host"

  prefix                  = var.name_prefix
  subnet_id               = aws_subnet.public_subnet[0].id
  vpc_id                  = aws_vpc.vpc.id
  vpc_cidr_block          = aws_vpc.vpc.cidr_block
  private_route_table_ids = [for prt in aws_route_table.private_route_table : prt.id]
}

# This resource is used in order to add dependencies on all resources 
# Any resource uses this VPC ID, must wait to all resources creation completion
resource "time_sleep" "vpc_resources_wait" {
  create_duration  = "20s"
  destroy_duration = "20s"
  triggers = {
    vpc_id                                           = aws_vpc.vpc.id
    cidr_block                                       = aws_vpc.vpc.cidr_block
    private_vpc_endpoint_route_table_association_ids = jsonencode([for value in aws_vpc_endpoint_route_table_association.private_vpc_endpoint_route_table_association : value.id])
    public_route_table_association_ids               = jsonencode([for value in aws_route_table_association.public_route_table_association : value.id])
    private_route_table_association_ids              = jsonencode([for value in aws_route_table_association.private_route_table_association : value.id])
    proxy_cert_path                                  = var.enable_transparent_proxy ? module.transparent-proxy[0].proxy_cert_path : ""
  }
}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  # New configuration to exclude Local Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

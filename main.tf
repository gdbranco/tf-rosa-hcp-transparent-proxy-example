module "vpc" {
  source = "./vpc"

  name_prefix              = var.prefix
  availability_zones_count = 1

  enable_transparent_proxy = true
}
module "bastion_host" {
  # Not yet available in official release
  source     = "github.com/terraform-redhat/terraform-rhcs-rosa-hcp//modules/bastion-host?ref=shared-vpc"
  prefix     = var.prefix
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.public_subnets[0]]
}
module "worker_host" {
  source         = "./worker-host"
  prefix         = var.prefix
  subnet_id      = module.vpc.private_subnets[0]
  vpc_cidr_block = module.vpc.cidr_block
  vpc_id         = module.vpc.vpc_id
}

variable "prefix" {
  type        = string
  description = "Prefix for the name of each AWS resource"
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR ranges to include as ingress allowed ranges"
}

variable "vpc_id" {
  type        = string
  description = "ID of the AWS VPC resource"
}

variable "subnet_id" {
  type        = string
  description = "ID of the AWS VPC resource"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type of the proxy host"
}

variable "ami_id" {
  type        = string
  default     = null
  description = "Amazon Machine Image to run the proxy host with"
}
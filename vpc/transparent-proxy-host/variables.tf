variable "prefix" {
  type        = string
  description = "Prefix for the name of each AWS resource"
}

variable "cidr_blocks" {
  type        = list(string)
  default     = null
  description = "CIDR ranges to include as ingress allowed ranges"
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

variable "ami_username" {
  type        = string
  default     = null
  description = "Username to log in to instance, ami based"
}

variable "user_data_file" {
  type        = string
  default     = null
  description = "User data for proxy configuration"
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "ID of the private route table resources"
}

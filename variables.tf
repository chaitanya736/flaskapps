variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Amazon Linux 2 AMI ID (update for your region)"
  type        = string
  default     = "ami-03446a3af42c5e74e"  # us-east-1 example; check AWS console for latest
}


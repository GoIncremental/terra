variable "base_ami" {}
variable "account" {}
variable "env" {}
variable "cidr_block" {}
variable "authorised_cidr" {}
variable "public_subnets" {}
variable "vpc_id" {}
variable "instance_type" {
  default = "t2.micro"
}
variable "zones" {}
variable flag {
  default = 0
}
variable "security_groups" {
  default = ""
}

################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "inbound" {
  name = "${var.account}-${var.env}-bastion-in"
  description = "Inbound rules for bastion hosts"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-bastion-in"   
    CostCenter = "${var.account}-${var.env}"
  }
  ingress {
    protocol = "tcp"
    from_port = 6042
    to_port = 6042
    cidr_blocks = ["${var.authorised_cidr}"]
  }
}

resource "aws_security_group" "outbound" {
  name = "${var.account}-${var.env}-bastion-out"
  description = "Refer to this group if you wish to accept traffic from the bastion"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-bastion-out"   
    CostCenter = "${var.account}-${var.env}"
  }
  lifecycle {
    create_before_destroy = true
  }
  egress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = ["${var.cidr_block}"]
  }
}

################################################################################
# Bastion instances
################################################################################
resource "template_file" "cloud_config" {
    template = "${file("${path.module}/cloud-config")}"
}

resource "aws_instance" "bastion" {
  ami = "${var.base_ami}"
  count = "${length(split(",",var.zones)) * var.flag}"
  instance_type = "${var.instance_type}"
  key_name = "${var.account}-${var.env}-bootstrap"
  subnet_id = "${element(split(",",var.public_subnets),count.index)}"
  user_data = "${template_file.cloud_config.rendered}"
  vpc_security_group_ids = [
    "${aws_security_group.inbound.id}",
    "${aws_security_group.outbound.id}", 
    "${compact(split(",", var.security_groups ))}"
  ]
  tags {
    Name = "${var.account}-${var.env}-bastion${format("%02d",count.index + 1)}"
    CostCenter = "${var.account}-${var.env}"
    Ansible = "bastion"
    Limit = "${var.account}_${var.env}_bastion"
  }

  lifecycle {
    ignore_changes = ["ami"]
  }
}

resource "aws_eip" "bastion" {
  count = "${length(split(",",var.zones)) * var.flag}"
  instance = "${element(aws_instance.bastion.*.id, count.index)}"
  vpc = true
}

output "sg" {value = "${aws_security_group.outbound.id}"}
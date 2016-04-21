variable base_ami {}
variable account {}
variable env {}
variable authorised_cidr {}
variable public_subnets {}
variable vpc_id {}
variable instance_type {
  default = "t2.micro"
}
variable zones {}

################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "inbound" {
  name = "${var.account}-${var.env}-bastion-in"
  description = "Inbound rules for bastion hosts"
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
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-bastion-out"   
    CostCenter = "${var.account}-${var.env}"
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
  count = "${length(split(",",var.zones))}"
  instance_type = "${var.instance_type}"
  key_name = "${var.account}-${var.env}-bootstrap"
  subnet_id = "${element(split(",",var.public_subnets),count.index)}"
  user_data = "${template_file.cloud_config.rendered}"
  vpc_security_group_ids = [
    "${aws_security_group.inbound.id}",
    "${aws_security_group.outbound.id}"
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
  count = "${length(split(",",var.zones))}"
  instance = "${element(aws_instance.bastion.*.id, count.index)}"
  vpc = true
}

output "sg" {value = "${aws_security_group.outbound.id}"}
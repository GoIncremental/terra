variable "base_ami" {}
variable "account" {}
variable "env" {}
variable "vpc_id" {}
variable "cidr_block" {}
variable "zones" {}
variable "bastion_sg" {}
variable "private_routetables" {}
variable "flag" {
  default = 0
}
variable "instance_type" {
  default = "t2.micro"
}
variable "cluster_size" {
  default = 3
}
variable "cluster_min_size" {
  default = 1
}
variable "cluster_max_size" {
  default = 9
}
variable "service_name" {
  default = "etcd"
}

################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "in" {
  name = "${var.account}-${var.env}-etcd-in"
  description = "Inbound rules for etcd hosts"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-etcd-in"
    CostCenter = "${var.account}-${var.env}"
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    security_groups = ["${var.bastion_sg}"]
  }
  ingress {
    protocol = "tcp"
    from_port = 2379
    to_port = 2379
    security_groups = [
      "${aws_security_group.out.id}",
      "${aws_security_group.client.id}"
    ]
  }
  ingress {
    protocol = "tcp"
    from_port = 2380
    to_port = 2380
    security_groups = [
      "${aws_security_group.out.id}",
      "${aws_security_group.proxy.id}"
    ]
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "out" {
  name = "${var.account}-${var.env}-etcd-out"
  description = "Refer to this group if you wish to accept traffic from etcd"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-etcd-out"
    CostCenter = "${var.account}-${var.env}"
  } 
  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["${var.cidr_block}"]
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
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "proxy" {
  name = "${var.account}-${var.env}-etcd-proxy-out"
  description = "Outbound Group for machines wishing to proxy to etcd"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-etcd-proxy"
    CostCenter = "${var.account}-${var.env}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "client" {
  name = "${var.account}-${var.env}-etcd-client-out"
  description = "Outbound Group for client machines wishing to access etcd"
  count = "${var.flag}"
  vpc_id = "${var.vpc_id}"
  tags = {
    Name       = "${var.account}-${var.env}-etcd-client"
    CostCenter = "${var.account}-${var.env}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

output "sg" {value = "${aws_security_group.out.id}"}
output "proxy_sg" {value = "${aws_security_group.proxy.id}"}
output "client_sg" {value = "${aws_security_group.client.id}"}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "etcd" {
  vpc_id = "${var.vpc_id}"
  cidr_block = "${cidrsubnet(var.cidr_block,10,800+count.index)}"
  count = "${length(split(",",var.zones)) * var.flag}"
  availability_zone = "${element(split(",",var.zones), count.index)}"
  tags { 
    Name = "${var.account}-${var.env}-${var.service_name}-${format("%02d",count.index + 1)}"
    CostCenter  = "${var.account}-${var.env}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "etcd" {
  count = "${length(split(",",var.zones)) * var.flag}"
  subnet_id = "${element(aws_subnet.etcd.*.id, count.index)}"
  route_table_id = "${element(split(",",var.private_routetables),count.index)}"
}

#############################################################################################################
# IAM Role, Policy and Attachment
#############################################################################################################

module "iam_role" {
  source   = "../iam_role/"
  flag     = "${var.flag}"
  account  = "${var.account}"
  env      = "${var.env}"
  svc_code = "etcd"
}

resource "aws_iam_policy" "etcd" {
   name = "${var.account}-${var.env}-${var.service_name}"
   description = "Allows members to describe other ec2 instances and auto scaling groups"
   policy = "${file("${path.module}/role-policy.json")}"
}

resource "aws_iam_policy_attachment" "etcd" {
   name = "${var.account}-${var.env}-${var.service_name}"
   roles = ["${module.iam_role.name}"]
   policy_arn = "${aws_iam_policy.etcd.arn}"
}


################################################################################
# Auto Scaling Group
################################################################################

# Launch configuration
resource "aws_launch_configuration" "lc" {
  name_prefix = "${var.account}-${var.env}-${var.service_name}-"
  count = "${var.flag}"
  image_id = "${var.base_ami}"
  instance_type = "${var.instance_type}"
  iam_instance_profile = "${module.iam_role.profile_id}"
  key_name = "${var.account}-${var.env}-internal"
  security_groups = [
    "${aws_security_group.in.id}",
    "${aws_security_group.out.id}"
  ]
  user_data = "${file("${path.module}/cloud-config")}"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg" {
  name = "${var.account}-${var.env}-etcd"
  count = "${var.flag}"
  launch_configuration = "${aws_launch_configuration.lc.name}"
  vpc_zone_identifier = ["${aws_subnet.etcd.*.id}"]
  desired_capacity = "${var.cluster_size}"
  min_size = "${var.cluster_min_size}"
  max_size = "${var.cluster_max_size}"
  tag { 
    key = "Name"
    value = "${var.account}-${var.env}-etcd-asg"
    propagate_at_launch = true
  }
  tag {
    key = "CostCenter"
    value = "${var.account}-${var.env}"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}
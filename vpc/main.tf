variable "account" {}
variable "env" {}
variable "cidr_octet_1" {
    default = 10
}
variable "cidr_octet_2" {
    default = 0
}

variable "zones" {
    default = "eu-west-1a,eu-west-1b,eu-west-1c"
}

variable "dns_support" {
    default = false
}
variable "dns_hostnames" {
    default = false
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "main" {
  cidr_block = "${var.cidr_octet_1}.${var.cidr_octet_2}.0.0/16"
  enable_dns_support = "${var.dns_support}"
  enable_dns_hostnames = "${var.dns_hostnames}"
  tags {
    Name     = "${var.account}-${var.env}-vpc"
    CostCode = "${var.account}-${var.env}"
    Env      = "${var.env}"
    Account  = "${var.account}"
  }
}

# Each VPC can have only one internet gateway
resource "aws_internet_gateway" "main" {
    vpc_id = "${aws_vpc.main.id}"
    tags {
        Name = "${var.account}-${var.env}"
        CostCode = "${var.account}-${var.env}"
    }
}

################################################################################
# Public Route Table
################################################################################

# We define a route table that allows access to any ip address through
# the internet gateway
resource "aws_route_table" "public" {
    vpc_id = "${aws_vpc.main.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.main.id}"
    }
    tags {
        Name     = "${var.account}-${var.env}-public"
        CostCode = "${var.account}-${var.env}"
    }
}


################################################################################
# Public Subnets
################################################################################

# Each VPC should have a Public subnet per AZ, that can route to the internet 
# gateway. The only machines we should put into that DMZ subnet should be our
# bastion VPN server and / or a NAT server configured to allow machines in other
# subnets to get access out to the internet.  ELBs as well perhaps?
resource "aws_subnet" "public" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "${cidrsubnet("${var.cidr_octet_1}.${var.cidr_octet_2}.1.0/16", 8, count.index)}"
    availability_zone = "${element(split(",",var.zones),count.index)}"
    tags {
        Name     = "${var.account}-${var.env}-public${format("%02d",count.index + 1)}"
        CostCode = "${var.account}-${var.env}"
    }
    count = "${length(split(",",var.zones))}"
}

# We associate the public route table with our public subnets, meaning only these
# subnets will be able to communicate directly with the internet
resource "aws_route_table_association" "public" {
    subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
    route_table_id = "${aws_route_table.public.id}"
    count = "${length(split(",",var.zones))}"
}


################################################################################
# NAT Gateways
################################################################################

# We launch a nat gateway in each of the public subnets so that (if desired) 
# private subnets can route out to the internet via these gateways

resource "aws_eip" "nat" {
  count = "${length(split(",",var.zones))}"
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  count = "${length(split(",",var.zones))}"
  allocation_id = "${element(aws_eip.nat.*.id,count.index)}"
  subnet_id = "${element(aws_subnet.public.*.id,count.index)}"
  depends_on = ["aws_internet_gateway.main"]
}


################################################################################
# Private Route Tables
################################################################################

# we need one private route table per AZ since each will route internet traffic
# through a separate NAT gateway also associated with that AZ to ensure we 
# maintain connectivity if a single AZ goes down

resource "aws_route_table" "private" {
  count = "${length(split(",",var.zones))}"
  vpc_id = "${aws_vpc.main.id}"
  route {
    cidr_block  = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.nat.*.id, count.index)}"
  }
  tags {
    Name     = "${var.account}-${var.env}-private"
    CostCode = "${var.account}-${var.env}"
  }
}
output "private_routetables" {value = "${join(",",aws_route_table.private.*.id)}"}
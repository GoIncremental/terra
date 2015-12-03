variable "env" {}
variable "tenant" {}
variable "cidr_block" {}
variable "zones" {
  default = {
    zone0 = "eu-west-1a"
    zone1 = "eu-west-1b"
    zone2 = "eu-west-1c"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "${var.cidr_block}.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags {
    Name   = "${var.tenant}-${var.env}"
    env    = "${var.env}"
    tenant = "${var.tenant}"
  }
}

# Each VPC can have only one internet gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.main.id}"

    tags {
        Name = "${var.tenant}-${var.env}"
    }
}

# We define a route table that allows access to any ip address through
# the internet gateway
resource "aws_route_table" "internet_route_table" {
    vpc_id = "${aws_vpc.main.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }

    tags {
        Name = "InternetRouteTable"
    }
}

# Each VPC should have a DMZ, connected to the internet gateway
# The only machines we should put into that DMZ subnet should be our bastion
# VPN server and / or a NAT server configured to allow machines in other
# subnets to get access out to the internet.
resource "aws_subnet" "dmz" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "${cidrsubnet("${var.cidr_block}.1.0/24", 2, count.index)}"
    availability_zone = "${lookup(var.zones, concat("zone", count.index))}"
    tags {
        Name = "${var.tenant}-${var.env}-dmz-${count.index}"
    }
    count = 3
}

# We associate the route table with our dmz subnet, meaning only that
# subnet will be able to communicate with the internet
resource "aws_route_table_association" "dmz" {
    subnet_id = "${element(aws_subnet.dmz.*.id, count.index)}"
    route_table_id = "${aws_route_table.internet_route_table.id}"
    count = 3
}

# We create subnets to hold our application layer, and
resource "aws_subnet" "app" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "${cidrsubnet("${var.cidr_block}.2.0/24", 2, count.index)}"
    availability_zone = "${lookup(var.zones, concat("zone", count.index))}"
    tags {
        Name = "${var.tenant}-${var.env}-app-${count.index}"
    }
    count = 3
}

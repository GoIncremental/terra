variable "account" {}
variable "env" {}
variable "svc_code" {}
variable "flag" {
  default = 0
}

resource "aws_iam_role" "svc_role" {
  name = "${var.account}-${var.env}-${var.svc_code}"
  count = "${var.flag}"
  assume_role_policy =  "${file("${path.module}/AssumeRole.json")}"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "svc_profile" {
  name = "${var.account}-${var.env}-${var.svc_code}"
  count = "${var.flag}"  
  roles = ["${aws_iam_role.svc_role.name}"]
  lifecycle {
    create_before_destroy = true
  }
}

output "name" {value = "${aws_iam_role.svc_role.name}"}
output "profile_id" {value = "${aws_iam_instance_profile.svc_profile.id}"}
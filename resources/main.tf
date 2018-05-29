provider "aws" {
  region = "eu-west-1"
}

/*
 * Create RDS database for concourse.
 *
 */

resource "aws_security_group" "concourse" {
  name        = "main_rds_sg"
  description = "Allow all inbound traffic"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    cidr_blocks = ["${var.cidr_blocks}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.sg_name}"
  }
}

resource "aws_db_subnet_group" "concourse" {
  name        = "main_subnet_group"
  description = "Our main group of subnets"
  subnet_ids  = ["${var.subnet_1_id}", "${var.subnet_2_id}"]
}

resource "aws_db_instance" "concourse" {
  depends_on             = ["aws_security_group.concourse"]
  identifier             = "${var.identifier}"
  allocated_storage      = "${var.storage}"
  engine                 = "${var.engine}"
  engine_version         = "${lookup(var.engine_version, var.engine)}"
  instance_class         = "${var.instance_class}"
  name                   = "${var.db_name}"
  username               = "${var.username}"
  password               = "${var.password}"
  vpc_security_group_ids = ["${aws_security_group.concourse.id}"]
  db_subnet_group_name   = "${aws_db_subnet_group.concourse.id}"
  skip_final_snapshot    = true
}

/*
 * Generate the `values.yaml` configuration for the concourse helm chart.
 *
 */

resource "tls_private_key" "host_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_private_key" "session_signing_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_private_key" "worker_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

data "template_file" "values" {
  template = "${file("${path.module}/templates/values.yaml")}"

  vars {
    concourse_image_tag       = "${var.concourse_image_tag}"
    github_auth_client_id     = "${var.github_auth_client_id}"
    github_auth_client_secret = "${var.github_auth_client_secret}"
    concourse_hostname        = "${var.concourse_hostname}"
    github_users              = "${join(",", var.github_users)}"
    postgresql_user           = "${aws_db_instance.concourse.username}"
    postgresql_password       = "${aws_db_instance.concourse.password}"
    postgresql_host           = "${aws_db_instance.concourse.address}"
    postgresql_sslmode        = false
    host_key_priv             = "${indent(4, tls_private_key.host_key.private_key_pem)}"
    host_key_pub              = "${tls_private_key.host_key.public_key_openssh}"
    session_signing_key_priv  = "${indent(4, tls_private_key.session_signing_key.private_key_pem)}"
    worker_key_priv           = "${indent(4, tls_private_key.worker_key.private_key_pem)}"
    worker_key_pub            = "${tls_private_key.worker_key.public_key_openssh}"
  }
}

resource "local_file" "values" {
  content  = "${data.template_file.values.rendered}"
  filename = "${path.module}/../concourse/values.yaml"
}

resource "aws_security_group" "appserver" {
  name   = "${var.app_identifier}-appserver"
  vpc_id = var.vpc_id
}

resource "aws_security_group" "rayo" {
  name   = "${var.app_identifier}-rayo"
  vpc_id = var.vpc_id

  ingress {
    from_port = 5222
    to_port   = 5222
    protocol  = "TCP"
    self      = true
  }
}

resource "aws_security_group_rule" "appserver_egress" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  from_port         = 0
  security_group_id = aws_security_group.appserver.id
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "smart_cambodia" {
  type        = "ingress"
  from_port   = 5060
  to_port     = 5060
  protocol    = "udp"
  cidr_blocks = ["27.109.112.140/32"]
  description = "Smart Cambodia"

  security_group_id = aws_security_group.appserver.id
}

resource "aws_security_group_rule" "cellcard_cambodia" {
  type        = "ingress"
  from_port   = 5060
  to_port     = 5060
  protocol    = "udp"
  cidr_blocks = ["103.193.204.26/32"]
  description = "Cellcard Cambodia"

  security_group_id = aws_security_group.appserver.id
}

resource "aws_security_group_rule" "metfone_cambodia" {
  type        = "ingress"
  from_port   = 5060
  to_port     = 5060
  protocol    = "udp"
  cidr_blocks = ["175.100.93.13/32"]
  description = "Metfone Cambodia"

  security_group_id = aws_security_group.appserver.id
}

resource "aws_security_group_rule" "c3ntro_mexico" {
  type        = "ingress"
  from_port   = 5060
  to_port     = 5060
  protocol    = "udp"
  cidr_blocks = ["200.0.90.35/32"]
  description = "c3ntro Mexico"

  security_group_id = aws_security_group.appserver.id
}

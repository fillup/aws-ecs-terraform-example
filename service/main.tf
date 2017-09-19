/*
 * Create RDS instance
 */
resource "aws_db_instance" "db_instance" {
  engine                 = "mariadb"
  allocated_storage      = "8"
  instance_class         = "db.t2.micro"
  name                   = "mydatabase"
  identifier             = "mydatabase"
  username               = "dbuser"
  password               = "dbpass1234"
  db_subnet_group_name   = "${data.terraform_remote_state.shared.db_subnet_group_name}"
  vpc_security_group_ids = ["${data.terraform_remote_state.shared.vpc_default_sg_id}"]
  skip_final_snapshot    = true
}

/*
 * Look up Amazon Certificate Manager cert
 */
data "aws_acm_certificate" "sslcert" {
  domain = "${var.cert_domain_name}"
}

/*
 * Create security group for public HTTPS access
 */
resource "aws_security_group" "public_https" {
  name        = "public-https"
  description = "Allow HTTPS traffic from public"
  vpc_id      = "${data.terraform_remote_state.shared.vpc_id}"
}

resource "aws_security_group_rule" "public_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.public_https.id}"
  cidr_blocks       = ["0.0.0.0/0"]
}

/*
 * Create application load balancer
 */
resource "aws_alb" "alb" {
  name            = "alb-myapp"
  internal        = false
  security_groups = ["${data.terraform_remote_state.shared.vpc_default_sg_id}", "${aws_security_group.public_https.id}"]
  subnets         = ["${data.terraform_remote_state.shared.public_subnet_ids}"]
}

/*
 * Create target group for ALB
 */
resource "aws_alb_target_group" "default" {
  name     = "tg-myapp"
  port     = "80"
  protocol = "HTTP"
  vpc_id   = "${data.terraform_remote_state.shared.vpc_id}"

  stickiness {
    type = "lb_cookie"
  }
}

/*
 * Create listeners to connect ALB to target group
 */
resource "aws_alb_listener" "https" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "${data.aws_acm_certificate.sslcert.arn}"

  default_action {
    target_group_arn = "${aws_alb_target_group.default.arn}"
    type             = "forward"
  }
}

/*
 * Render task definition from template
 */
data "template_file" "task_def" {
  template = "${file("${path.module}/task-definition.json")}"

  vars {
    mysql_host = "${aws_db_instance.db_instance.address}"
    hostname   = "https://${aws_alb.alb.dns_name}/"
  }
}

/*
 * Create task definition
 */
resource "aws_ecs_task_definition" "td" {
  family                = "myapp"
  container_definitions = "${data.template_file.task_def.rendered}"
  network_mode          = "bridge"
}

/*
 * Create ECS Service
 */
resource "aws_ecs_service" "service" {
  name                               = "myapp"
  cluster                            = "${data.terraform_remote_state.shared.ecs_cluster_name}"
  desired_count                      = "${length(data.terraform_remote_state.shared.aws_zones)}"
  iam_role                           = "${data.terraform_remote_state.shared.ecsServiceRole_arn}"
  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "50"

  placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.default.arn}"
    container_name   = "web"
    container_port   = "80"
  }

  task_definition = "${aws_ecs_task_definition.td.family}:${aws_ecs_task_definition.td.revision}"
}

/*
 * Create Cloudflare DNS record
 */
resource "cloudflare_record" "pmadns" {
  domain  = "${var.cloudflare_domain}"
  name    = "pma"
  value   = "${aws_alb.alb.dns_name}"
  type    = "CNAME"
  proxied = true
}

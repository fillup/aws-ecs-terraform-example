output "url" {
  value = "https://pma.${var.cloudflare_domain}"
}

output "dbusername" {
  value = "${aws_db_instance.db_instance.username}"
}

output "dbpassword" {
  value = "${aws_db_instance.db_instance.password}"
}

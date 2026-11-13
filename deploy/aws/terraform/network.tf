data "aws_availability_zones" "available" {
  state = "available"
}
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : 2
  domain = "vpc"
}
resource "aws_nat_gateway" "main" {
  count         = var.single_nat_gateway ? 1 : 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]
}
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
}
resource "aws_route" "nat" {
  count                  = 2
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
}
resource "aws_security_group" "service" {
  for_each    = toset(["web", "collector", "alb", "db", "efs"])
  name_prefix = "${var.name}-${each.key}-"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  for_each          = toset(["web", "collector", "alb"])
  security_group_id = aws_security_group.service[each.key].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "db" {
  for_each                     = toset(["web", "collector"])
  security_group_id            = aws_security_group.service["db"].id
  referenced_security_group_id = aws_security_group.service[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_vpc_security_group_ingress_rule" "efs" {
  security_group_id            = aws_security_group.service["efs"].id
  referenced_security_group_id = aws_security_group.service["collector"].id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
}
resource "aws_vpc_security_group_ingress_rule" "web" {
  security_group_id            = aws_security_group.service["web"].id
  referenced_security_group_id = aws_security_group.service["alb"].id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

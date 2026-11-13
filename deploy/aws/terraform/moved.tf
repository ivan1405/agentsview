moved {
  from = aws_vpc_security_group_ingress_rule.efs
  to   = aws_vpc_security_group_ingress_rule.efs[0]
}
moved {
  from = aws_vpc_security_group_ingress_rule.web
  to   = aws_vpc_security_group_ingress_rule.web[0]
}
moved {
  from = aws_efs_file_system_policy.collector
  to   = aws_efs_file_system_policy.collector[0]
}

##
## General Environment Setup
##
provider "aws" {
  region = var.awsRegion
}
data "aws_availability_zones" "available" {
  state = "available"
}
resource "tls_private_key" "newkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}
resource "local_file" "newkey_pem" { 
  # create a new local ssh identity
  filename = "${abspath(path.root)}/.ssh/${var.projectPrefix}-key-${random_id.buildSuffix.hex}.pem"
  sensitive_content = tls_private_key.newkey.private_key_pem
  file_permission = "0400"
}
resource "aws_key_pair" "deployer" {
  # create a new AWS ssh identity
  key_name = "${var.projectPrefix}-key-${random_id.buildSuffix.hex}"
  public_key = tls_private_key.newkey.public_key_openssh
}
data "http" "ip_address" {
  # retrieve the local public IP address
  url = var.get_address_url
  request_headers = var.get_address_request_headers
}
data "http" "ipv6_address" {
  # trieve the local public IPv6 address
  url = var.get_address_url_ipv6
  request_headers = var.get_address_request_headers
}

data "aws_caller_identity" "current" {
  # Get the current AWS caller identity
}

##
## Locals
##

locals {
  awsAz1 = var.awsAz1 != null ? var.awsAz1 : data.aws_availability_zones.available.names[0]
  awsAz2 = var.awsAz2 != null ? var.awsAz1 : data.aws_availability_zones.available.names[1]
}

##
## Juice Shop VM AMI - Ubuntu
##

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

##
## BIG-IP AMI - F5
##

data "aws_ami" "F5BIG-IP_AMI" {
  most_recent = true
  name_regex = ".*${lookup(var.bigip_ami_mapping, var.bigipLicenseType)}.*"

  filter {
    name = "name"
    values = ["F5 BIGIP-${var.bigip_version}*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

################
## F5 BIG-IPs ##
################

##
## VPC
##

resource "aws_vpc" "SecuritySvcsVPC" {
  cidr_block = var.SecuritySvcsCIDR
  assign_generated_ipv6_cidr_block = "true"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsVPC-${random_id.buildSuffix.hex}"
    Owner = "${var.resourceOwner}"
  }
}

resource "aws_default_security_group" "SecuritySvcsSG" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
    tags = {
      Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSG-${random_id.buildSuffix.hex}"
  }
  ingress {
    protocol = -1
    self = true
    from_port = 0
    to_port = 0
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = -1
    from_port = 0
    to_port = 0
    cidr_blocks = [var.ServerSubnetCIDR,var.ClientSubnetCIDR,var.SecuritySvcsCIDR]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ1-MGMT" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ1-MGMT
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 1)}"
  assign_ipv6_address_on_creation = true
    tags = {
      Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ1-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ1-DATA" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ1-DATA
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 3)}"
  assign_ipv6_address_on_creation = true
    tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ1-DATA-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ1-DATA-ingress" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ1-DATA-ingress
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 5)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ1-DATA-ingress--${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ2-MGMT" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ2-MGMT
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ2-MGMT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ2-DATA" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ2-DATA
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 4)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ2-DATA-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "SecuritySvcsSubnetAZ2-DATA-ingress" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  cidr_block = var.SecuritySvcsSubnetAZ2-DATA-ingress
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.SecuritySvcsVPC.ipv6_cidr_block, 8, 6)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsSubnetAZ2-DATA-ingress-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "SecuritySvcsIGW" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_route_table" "SecuritySvcsMgmtRT" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.SecuritySvcsIGW.id
    }
  route {
      ipv6_cidr_block = "::/0"
      gateway_id = aws_internet_gateway.SecuritySvcsIGW.id
    }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsMgmtRT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_route_table_association" "SecuritySvcsMgmtRTAssociationAZ1" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ1-MGMT.id
  route_table_id = aws_route_table.SecuritySvcsMgmtRT.id
}

resource "aws_route_table_association" "SecuritySvcsMgmtRTAssociationAZ2" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ2-MGMT.id
  route_table_id = aws_route_table.SecuritySvcsMgmtRT.id
}

resource "aws_default_route_table" "SecuritySvcsMainRT" {
  default_route_table_id = aws_vpc.SecuritySvcsVPC.default_route_table_id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsMainRT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_route_table" "SecuritySvcsTGWRT" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.SecuritySvcsIGW.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.SecuritySvcsIGW.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ1.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ1.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ1.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ2.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ2.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ1.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ1.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ2.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ2.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-SecuritySvcsTGWRT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_route_table_association" "SecuritySvcsTGWRTAssociationAZ1" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ1-DATA.id
  route_table_id = aws_route_table.SecuritySvcsTGWRT.id
}

resource "aws_route_table_association" "SecuritySvcsTGWRTAssociationAZ2" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ2-DATA.id
  route_table_id = aws_route_table.SecuritySvcsTGWRT.id
}

## 
## BIG-IP AMI/Onboarding Config
##

data "template_file" "bigip_runtime_init_AZ1" {
  template = "${file("${path.module}/bigip_runtime_init_user_data.tpl")}"
  vars = {
    bigipAdminPassword = "${var.bigipAdminPassword}"
    bigipLicenseType = "${var.bigipLicenseType == "BYOL" ? "BYOL" : "PAYG"}"
    bigipLicense = "${var.bigipLicenseAZ1}"
    f5_do_version = "${var.f5_do_version}"
    f5_do_schema_version = "${var.f5_do_schema_version}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
    f5_ts_version = "${var.f5_ts_version}"
    f5_ts_schema_version = "${var.f5_ts_schema_version}"
    f5_cf_version = "${var.f5_cf_version}"
    service_address = "${aws_network_interface.F5_BIGIP_AZ1ENI_DATA.private_ip}"
    monitoring_address = "${aws_network_interface.F5_BIGIP_AZ1ENI_DATA.private_ip}"
    cm_self_hostname = "${var.projectPrefix}-bigip-PRI-AZ1.${var.labDomain}"
  }
}


data "template_file" "bigip_runtime_init_AZ2" {
  template = "${file("${path.module}/bigip_runtime_init_user_data.tpl")}"
  vars = {
    bigipAdminPassword = "${var.bigipAdminPassword}"
    bigipLicenseType = "${var.bigipLicenseType == "BYOL" ? "BYOL" : "PAYG"}"
    bigipLicense = "${var.bigipLicenseAZ2}"
    f5_do_version = "${var.f5_do_version}"
    f5_do_schema_version = "${var.f5_do_schema_version}"
    f5_as3_version = "${var.f5_as3_version}"
    f5_as3_schema_version = "${var.f5_as3_schema_version}"
    f5_ts_version = "${var.f5_ts_version}"
    f5_ts_schema_version = "${var.f5_ts_schema_version}"
    f5_cf_version = "${var.f5_cf_version}"
    service_address = "${aws_network_interface.F5_BIGIP_AZ2ENI_DATA.private_ip}"    
    monitoring_address = "${aws_network_interface.F5_BIGIP_AZ2ENI_DATA.private_ip}"
    cm_self_hostname = "${var.projectPrefix}-bigip-PRI-AZ2.${var.labDomain}"
  }
}


##
## AZ1 F5 BIG-IP Primary
##

resource "aws_network_interface" "F5_BIGIP_AZ1ENI_DATA" {
  source_dest_check = false
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ1-DATA.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ1ENI_DATA"
  }
}

resource "aws_network_interface" "F5_BIGIP_AZ1ENI_MGMT" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ1-MGMT.id
  # Disable IPV6 dual stack management because it breaks DO clustering
  ipv6_address_count = 0
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ1ENI_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ1EIP_MGMT" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.SecuritySvcsIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ1EIP_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ1EIP_DATA" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.SecuritySvcsIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ1EIP_DATA"
  }
}
resource "aws_instance" "F5_BIGIP_AZ1" {
  ami = data.aws_ami.F5BIG-IP_AMI.id
  instance_type = "${var.bigip_ec2_instance_type}"
  availability_zone = local.awsAz1
  key_name = aws_key_pair.deployer.id
	user_data = "${data.template_file.bigip_runtime_init_AZ1.rendered}"
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ1ENI_MGMT.id
    device_index = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ1ENI_DATA.id
    device_index = 1
  }
  # Let's ensure an EIP is provisioned so licensing and bigip-runtime-init runs successfully
  depends_on = [
    aws_eip.F5_BIGIP_AZ1EIP_MGMT
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-F5_BIGIP_AZ1-${random_id.buildSuffix.hex}"
  }
}


##
## AZ2 F5 BIG-IP
##

resource "aws_network_interface" "F5_BIGIP_AZ2ENI_DATA" {
  source_dest_check = false
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ2-DATA.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ2ENI_DATA"
  }
}

resource "aws_network_interface" "F5_BIGIP_AZ2ENI_MGMT" {
  subnet_id = aws_subnet.SecuritySvcsSubnetAZ2-MGMT.id
  # Disable IPV6 dual stack management because it breaks DO clustering
  ipv6_address_count = 0
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ2ENI_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ2EIP_MGMT" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.SecuritySvcsIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ2EIP_MGMT"
  }
}

resource "aws_eip" "F5_BIGIP_AZ2EIP_DATA" {
  vpc = true
  network_interface = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.id
  associate_with_private_ip = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.SecuritySvcsIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "F5_BIGIP_AZ2EIP_DATA"
  }
}

resource "aws_instance" "F5_BIGIP_AZ2" {
  ami = data.aws_ami.F5BIG-IP_AMI.id
  instance_type = "${var.bigip_ec2_instance_type}"
  availability_zone = local.awsAz2
  key_name = aws_key_pair.deployer.id
	user_data = "${data.template_file.bigip_runtime_init_AZ2.rendered}"
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ2ENI_MGMT.id
    device_index = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.F5_BIGIP_AZ2ENI_DATA.id
    device_index = 1
  }
  # Let's ensure an EIP is provisioned so licensing and bigip-runtime-init runs successfully
  depends_on = [
    aws_eip.F5_BIGIP_AZ2EIP_MGMT
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-F5_BIGIP_AZ2-${random_id.buildSuffix.hex}"
  }
}

resource "aws_lb" "BIGIP_GWLB" {
  name = "${var.projectPrefix}-BIGIP-GWLB-${random_id.buildSuffix.hex}"
  load_balancer_type = "gateway"
  enable_cross_zone_load_balancing = true
  subnet_mapping {
    subnet_id = aws_subnet.SecuritySvcsSubnetAZ1-DATA.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.SecuritySvcsSubnetAZ2-DATA.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-BIGIP_GWLB-${random_id.buildSuffix.hex}"
  }
}

resource "aws_lb_target_group" "BIGIP_GWLB_TG" {
  name = "${var.projectPrefix}-BIGIP-GWLB-TG-${random_id.buildSuffix.hex}"
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  port = 6081
  protocol = "GENEVE"
  health_check {
    port = 65530
    protocol = "HTTP"
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 2
    interval = 5
  }
}

resource "aws_lb_listener" "BIGIP_GWLB_Listener" {
  load_balancer_arn = aws_lb.BIGIP_GWLB.arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.BIGIP_GWLB_TG.arn
  }
}

resource "aws_lb_target_group_attachment" "BIGIPGWLBTGAttachmentAZ1" {
  target_group_arn = aws_lb_target_group.BIGIP_GWLB_TG.arn
  target_id = aws_instance.F5_BIGIP_AZ1.id
}

resource "aws_lb_target_group_attachment" "BIGIPGWLBTGAttachmentAZ2" {
  target_group_arn = aws_lb_target_group.BIGIP_GWLB_TG.arn
  target_id = aws_instance.F5_BIGIP_AZ2.id
}

resource "aws_vpc_endpoint_service" "BIGIP_GWLB_VPC_Endpoint_Service" {
  acceptance_required = false
  allowed_principals = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
  gateway_load_balancer_arns = [ aws_lb.BIGIP_GWLB.arn ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-BIGIP_GWLB_VPC_ES-${random_id.buildSuffix.hex}"
  }
}

resource "aws_vpc_endpoint" "BIGIPGWLBServerEndpointAZ1" {
  service_name = aws_vpc_endpoint_service.BIGIP_GWLB_VPC_Endpoint_Service.service_name
  vpc_id = aws_vpc.ServerVPC.id
  vpc_endpoint_type = aws_vpc_endpoint_service.BIGIP_GWLB_VPC_Endpoint_Service.service_type
  subnet_ids = [ aws_subnet.ServerSubnetEgressAZ1.id ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-BIGIPGWLBServerEndpoint-${random_id.buildSuffix.hex}"
  }
}

resource "aws_vpc_endpoint" "BIGIPGWLBServerEndpointAZ2" {
  service_name = aws_vpc_endpoint_service.BIGIP_GWLB_VPC_Endpoint_Service.service_name
  vpc_id = aws_vpc.ServerVPC.id
  vpc_endpoint_type = aws_vpc_endpoint_service.BIGIP_GWLB_VPC_Endpoint_Service.service_type
  subnet_ids = [ aws_subnet.ServerSubnetEgressAZ2.id ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-BIGIPGWLBServerEndpoint-${random_id.buildSuffix.hex}"
  }
}

############################################################
########################## Client ##########################
############################################################

##
## VPC
##

resource "aws_vpc" "ClientVPC" {
  cidr_block = var.ClientSubnetCIDR
  assign_generated_ipv6_cidr_block = "true"  
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "ClientSG" {
  vpc_id = aws_vpc.ClientVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientSG-${random_id.buildSuffix.hex}"
  }
  ingress {
    protocol = -1
    self = true
    from_port = 0
    to_port = 0
  }
  ingress {
    protocol = -1
    from_port = 0
    to_port = 0
    cidr_blocks = [aws_subnet.ServerSubnetAZ1.cidr_block,aws_subnet.ServerSubnetAZ2.cidr_block]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "ClientSubnetAZ1" {
  vpc_id = aws_vpc.ClientVPC.id
  cidr_block = var.ClientSubnetAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ClientVPC.ipv6_cidr_block, 8, 1)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientSubnetAZ1-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "ClientSubnetAZ2" {
  vpc_id = aws_vpc.ClientVPC.id
  cidr_block = var.ClientSubnetAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ClientVPC.ipv6_cidr_block, 8, 2)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientSubnetAZ2-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "ClientIGW" {
  vpc_id = aws_vpc.ClientVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "ClientMainRT" {
  default_route_table_id = aws_vpc.ClientVPC.default_route_table_id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.ClientIGW.id
    }
  route {
      ipv6_cidr_block = "::/0"
      gateway_id = aws_internet_gateway.ClientIGW.id
    }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ1.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ1.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ServerSubnetAZ2.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ServerSubnetAZ2.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientMainRT-${random_id.buildSuffix.hex}"
  }
}

##
## Client Server AZ1
##

resource "aws_network_interface" "ClientAZ1ENI" {
  subnet_id = aws_subnet.ClientSubnetAZ1.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ClientAZ1ENI"
  }
}

resource "aws_eip" "ClientAZ1EIP" {
  vpc = true
  network_interface = aws_network_interface.ClientAZ1ENI.id
  associate_with_private_ip = aws_network_interface.ClientAZ1ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ClientIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ClientAZ1EIP"
  }
}

resource "aws_instance" "ClientAZ1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ClientEC2InstanceType}"
  availability_zone = local.awsAz1
  key_name = aws_key_pair.deployer.id
	user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt -y upgrade
              sudo apt -y install apt-transport-https ca-certificates curl software-properties-common docker
              sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
              sudo apt update
              sudo apt-cache policy docker-ce
              sudo apt -y install docker-ce
              sudo usermod -aG docker ubuntu
              docker pull bkimminich/juice-shop
              docker run -d -p 80:3000 --restart unless-stopped bkimminich/juice-shop
              sudo reboot
              EOF    
  network_interface {
    network_interface_id = aws_network_interface.ClientAZ1ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ClientAZ1EIP
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientAZ1-${random_id.buildSuffix.hex}"
  }
}

##
## Client AZ2
##

resource "aws_network_interface" "ClientAZ2ENI" {
  subnet_id = aws_subnet.ClientSubnetAZ2.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ClientAZ2ENI"
  }
}

resource "aws_eip" "ClientAZ2EIP" {
  vpc = true
  network_interface = aws_network_interface.ClientAZ2ENI.id
  associate_with_private_ip = aws_network_interface.ClientAZ2ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ClientIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ClientAZ2EIP"
  }
}

resource "aws_instance" "ClientAZ2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ClientEC2InstanceType}"
  availability_zone = local.awsAz2
  key_name = aws_key_pair.deployer.id
	user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt -y upgrade
              sudo apt -y install apt-transport-https ca-certificates curl software-properties-common docker
              sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
              sudo apt update
              sudo apt-cache policy docker-ce
              sudo apt -y install docker-ce
              sudo usermod -aG docker ubuntu
              docker pull bkimminich/juice-shop
              docker run -d -p 80:3000 --restart unless-stopped bkimminich/juice-shop
              sudo reboot
              EOF    
  network_interface {
    network_interface_id = aws_network_interface.ClientAZ2ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ClientAZ2EIP
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ClientAZ2-${random_id.buildSuffix.hex}"
  }
}

############################################################
########################## Server ##########################
############################################################

##
## VPC
##

resource "aws_vpc" "ServerVPC" {
  cidr_block = var.ServerSubnetCIDR
  assign_generated_ipv6_cidr_block = "true"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerVPC-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_security_group" "ServerSG" {
  vpc_id = aws_vpc.ServerVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSG-${random_id.buildSuffix.hex}"
  }
  ingress {
    protocol = -1
    self = true
    from_port = 0
    to_port = 0
  }
  ingress {
    protocol = -1
    from_port = 0
    to_port = 0
    cidr_blocks = [aws_subnet.ClientSubnetAZ1.cidr_block,aws_subnet.ClientSubnetAZ2.cidr_block]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = [format("%s/%s",data.http.ip_address.body,32)]
  }
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    ipv6_cidr_blocks = [format("%s/%s",data.http.ipv6_address.body,128)]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "ServerSubnetAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 10)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetAZ1-${random_id.buildSuffix.hex}"
  }
}

resource "aws_subnet" "ServerSubnetIngressAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetIngressAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 11)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetIngressAZ1-${random_id.buildSuffix.hex}"
  }
}
resource "aws_subnet" "ServerSubnetEgressAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetEgressAZ1
  availability_zone = local.awsAz1
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 12)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetEgressAZ1-${random_id.buildSuffix.hex}"
  }
}
resource "aws_subnet" "ServerSubnetAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 20)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetAZ2-${random_id.buildSuffix.hex}"
  }
}
resource "aws_subnet" "ServerSubnetIngressAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetIngressAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 21)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetIngressAZ2-${random_id.buildSuffix.hex}"
  }
}
resource "aws_subnet" "ServerSubnetEgressAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  cidr_block = var.ServerSubnetEgressAZ2
  availability_zone = local.awsAz2
  ipv6_cidr_block = "${cidrsubnet(aws_vpc.ServerVPC.ipv6_cidr_block, 8, 22)}"
  assign_ipv6_address_on_creation = true
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerSubnetEgressAZ2-${random_id.buildSuffix.hex}"
  }
}

resource "aws_internet_gateway" "ServerIGW" {
  vpc_id = aws_vpc.ServerVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerIGW-${random_id.buildSuffix.hex}"
  }
}

resource "aws_default_route_table" "ServerMainRT" {
  default_route_table_id = aws_vpc.ServerVPC.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ1.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ1.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    cidr_block = aws_subnet.ClientSubnetAZ2.cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  route {
    ipv6_cidr_block = aws_subnet.ClientSubnetAZ2.ipv6_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerMainRT-${random_id.buildSuffix.hex}"
  }
}

resource "aws_route_table" "ServerIngressGWLBeAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  route {
    cidr_block = aws_subnet.ServerSubnetAZ1.cidr_block
    vpc_endpoint_id = aws_vpc_endpoint.BIGIPGWLBServerEndpointAZ1.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerIngressGWLBeAZ1-${random_id.buildSuffix.hex}"
  }  
}

resource "aws_route_table_association" "ServerIngressGWLBeAZ1" {
  subnet_id = aws_subnet.ServerSubnetIngressAZ1.id
  route_table_id = aws_route_table.ServerIngressGWLBeAZ1.id
}

resource "aws_route_table" "ServerIngressGWLBeAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerIngressGWLBeAZ2-${random_id.buildSuffix.hex}"
  }  
}

resource "aws_route_table_association" "ServerIngressGWLBeAZ2" {
  subnet_id = aws_subnet.ServerSubnetIngressAZ2.id
  route_table_id = aws_route_table.ServerIngressGWLBeAZ2.id
}

resource "aws_route_table" "ServerEgressGWLBeAZ1" {
  vpc_id = aws_vpc.ServerVPC.id
  route {
    cidr_block = aws_vpc.ClientVPC.cidr_block
    vpc_endpoint_id = aws_vpc_endpoint.BIGIPGWLBServerEndpointAZ1.id
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerEgressGWLBeAZ1-${random_id.buildSuffix.hex}"
  }  
}

resource "aws_route_table_association" "ServerEgressGWLBeAZ1" {
  subnet_id = aws_subnet.ServerSubnetAZ1.id
  route_table_id = aws_route_table.ServerEgressGWLBeAZ1.id
}

resource "aws_route_table" "ServerEgressGWLBeAZ2" {
  vpc_id = aws_vpc.ServerVPC.id
  route {
    cidr_block = aws_vpc.ClientVPC.cidr_block
    vpc_endpoint_id = aws_vpc_endpoint.BIGIPGWLBServerEndpointAZ2.id
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ServerIGW.id
  }
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerEgressGWLBeAZ2-${random_id.buildSuffix.hex}"
  }  
}

resource "aws_route_table_association" "ServerEgressGWLBeAZ2" {
  subnet_id = aws_subnet.ServerSubnetAZ2.id
  route_table_id = aws_route_table.ServerEgressGWLBeAZ1.id
}

##
## Server Server AZ1
##

resource "aws_network_interface" "ServerAZ1ENI" {
  subnet_id = aws_subnet.ServerSubnetAZ1.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ServerAZ1ENI"
  }
}

resource "aws_eip" "ServerAZ1EIP" {
  vpc = true
  network_interface = aws_network_interface.ServerAZ1ENI.id
  associate_with_private_ip = aws_network_interface.ServerAZ1ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ServerAZ1EIP"
  }
}

resource "aws_instance" "ServerAZ1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ServerEC2InstanceType}"
  availability_zone = local.awsAz1
  key_name = aws_key_pair.deployer.id
	user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt -y upgrade
              sudo apt -y install apt-transport-https ca-certificates curl software-properties-common docker
              sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
              sudo apt update
              sudo apt-cache policy docker-ce
              sudo apt -y install docker-ce
              sudo usermod -aG docker ubuntu
              docker pull bkimminich/juice-shop
              docker run -d -p 80:3000 --restart unless-stopped bkimminich/juice-shop
              sudo reboot
              EOF    
  network_interface {
    network_interface_id = aws_network_interface.ServerAZ1ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ServerAZ1EIP
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerAZ1-${random_id.buildSuffix.hex}"
  }
}

##
## Server AZ2
##

resource "aws_network_interface" "ServerAZ2ENI" {
  subnet_id = aws_subnet.ServerSubnetAZ2.id
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ServerAZ2ENI"
  }
}

resource "aws_eip" "ServerAZ2EIP" {
  vpc = true
  network_interface = aws_network_interface.ServerAZ2ENI.id
  associate_with_private_ip = aws_network_interface.ServerAZ2ENI.private_ip
  # The IGW needs to exist before the EIP can be created
  depends_on = [
    aws_internet_gateway.ServerIGW
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "ServerAZ2EIP"
  }
}

resource "aws_instance" "ServerAZ2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "${var.ServerEC2InstanceType}"
  availability_zone = local.awsAz2
  key_name = aws_key_pair.deployer.id
	user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt -y upgrade
              sudo apt -y install apt-transport-https ca-certificates curl software-properties-common docker
              sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
              sudo apt update
              sudo apt-cache policy docker-ce
              sudo apt -y install docker-ce
              sudo usermod -aG docker ubuntu
              docker pull bkimminich/juice-shop
              docker run -d -p 80:3000 --restart unless-stopped bkimminich/juice-shop
              sudo reboot
              EOF    
  network_interface {
    network_interface_id = aws_network_interface.ServerAZ2ENI.id
    device_index = 0
  }
  # Let's ensure an EIP is provisioned so user-data can run successfully
  depends_on = [
    aws_eip.ServerAZ2EIP
  ]
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-ServerAZ2-${random_id.buildSuffix.hex}"
  }
}

##
## Transit Gateway
##

resource "aws_ec2_transit_gateway" "awsTransitGateway" {
  description = "Transit Gateway"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-tgw-${random_id.buildSuffix.hex}"
  }
}

### TGW Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "clientTGWVPCAttachment" {
  vpc_id = aws_vpc.ClientVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.ClientSubnetAZ1.id,aws_subnet.ClientSubnetAZ2.id]
  transit_gateway_default_route_table_association = "true"
  transit_gateway_default_route_table_propagation = "true"
  ipv6_support = "enable"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-client-tgwvpcattach-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "serverTGWVPCAttachment" {
  vpc_id = aws_vpc.ServerVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.ServerSubnetIngressAZ1.id,aws_subnet.ServerSubnetIngressAZ2.id]
  transit_gateway_default_route_table_association = "true"
  transit_gateway_default_route_table_propagation = "true"
  ipv6_support = "enable"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-server-tgwvpcattach-${random_id.buildSuffix.hex}"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "securityTGWVPCAttachment" {
  vpc_id = aws_vpc.SecuritySvcsVPC.id
  transit_gateway_id = aws_ec2_transit_gateway.awsTransitGateway.id
  subnet_ids = [aws_subnet.SecuritySvcsSubnetAZ1-DATA-ingress.id,aws_subnet.SecuritySvcsSubnetAZ2-DATA-ingress.id]
  transit_gateway_default_route_table_association = "true"
  transit_gateway_default_route_table_propagation = "true"
  ipv6_support = "enable"
  tags = {
    Owner = "${var.resourceOwner}"
    Name = "${var.projectPrefix}-security-tgwvpcattach-${random_id.buildSuffix.hex}"
  }  
}

# Create a random id
resource "random_id" "rix" {
	byte_length = 4
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
	cidr_block = "10.0.0.0/26"
	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

data "aws_ssm_parameter" "ami_id" {
  name = "automationamiimage"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
	vpc_id = aws_vpc.default.id
	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
	route_table_id         = aws_vpc.default.main_route_table_id
	destination_cidr_block = "0.0.0.0/0"
	gateway_id             = aws_internet_gateway.default.id
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
	availability_zone = var.aws_zone
	vpc_id                  = aws_vpc.default.id
	cidr_block              = "10.0.0.0/26"
	map_public_ip_on_launch = true
	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
	name        = "${var.prefix[0]}-${var.prefix[1]}-${random_id.rix.hex}-sgelb"
	description = "Used in the terraform"
	vpc_id      = aws_vpc.default.id

	# HTTP access from anywhere
	ingress {
		from_port   = 80
		to_port     = 80
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	# outbound internet access
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
	name        = "${var.prefix[0]}-${var.prefix[1]}-${random_id.rix.hex}-sgdefault"
	description = "Used in the terraform"
	vpc_id      = aws_vpc.default.id

	# SSH access from anywhere
	ingress {
		from_port   = 22
		to_port     = 22
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	# HTTP access from the VPC
	ingress {
		from_port   = 80
		to_port     = 80
		protocol    = "tcp"
		cidr_blocks = ["10.0.0.0/16"]
	}

	# outbound internet access
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

resource "aws_elb" "web" {
	name = "${var.prefix[0]}-${var.prefix[1]}-${random_id.rix.hex}-elb"

	subnets         = [aws_subnet.default.id]
	security_groups = [aws_security_group.elb.id]
	instances       = [aws_instance.web.id]

	listener {
		instance_port     = 80
		instance_protocol = "http"
		lb_port           = 80
		lb_protocol       = "http"
	}

	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

resource "aws_key_pair" "auth" {
	key_name   = "${var.key_name}-${random_id.rix.hex}"
	public_key = file(var.public_key_path)
	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}

resource "aws_instance" "web" {
	# The connection block tells our provisioner how to
	# communicate with the resource (instance)
	connection {
		type = "ssh"
		# The default username for our AMI
		user = "ubuntu"
		host = self.public_ip
		# The connection will use the local SSH agent for authentication.
	}

	instance_type = "c1.medium"

	# Lookup the correct AMI based on the region
	# we specified
	#ami = var.aws_amis[var.aws_region]
	ami = data.aws_ssm_parameter.ami_id.value
	# The name of our SSH keypair we created above.
	key_name = aws_key_pair.auth.id

	# Our Security group to allow HTTP and SSH access
	vpc_security_group_ids = [aws_security_group.default.id]

	# We're going to launch into the same subnet as our ELB. In a production
	# environment it's more common to have a separate private subnet for
	# backend instances.
	subnet_id = aws_subnet.default.id

	# We run a remote provisioner on the instance after creating it.
	# In this case, we just install nginx and start it. By default,
	# this should be on port 80
	#provisioner "remote-exec" {
	#  inline = [
	#    "sudo apt-get -y update",
	#    "sudo apt-get -y install nginx",
	#    "sudo service nginx start",
	#  ]
	#}
	availability_zone = "${var.aws_zone}"

	tags = {
		Name = "${var.prefix[0]}-${var.prefix[1]}"
	}
}
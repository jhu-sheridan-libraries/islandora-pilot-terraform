provider "aws" {}

terraform {
	backend "s3" {
	  bucket = "msel-ops-terraform-statefiles"
	  key = "applications/i8p"
	  region = "us-east-1"
	}
}

locals {
    tags = merge(
        {
            Environment = terraform.workspace
        },
        var.common_tags
    )

    public_subnet_ids = [ aws_subnet.public_primary.id, aws_subnet.public_secondary.id ]
}

resource "aws_vpc" "main" {
    cidr_block = "172.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = merge(
        {
            Name = format("i8p-%s", terraform.workspace)
        },
        local.tags
    )
}

resource "aws_subnet" "public_primary" {
    vpc_id            = aws_vpc.main.id
    availability_zone = "us-east-1a"
    cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, 8, 10)}"

    map_public_ip_on_launch = true
    tags = merge(
        {
            Name = format("i8p-public-primary-%s", terraform.workspace)
            Environment = terraform.workspace
        },
        local.tags
    )
}

resource "aws_subnet" "public_secondary" {
    vpc_id = aws_vpc.main.id
    availability_zone = "us-east-1c"
    cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, 20)
    map_public_ip_on_launch = true
    tags = merge(
        {
            Name = format("i8p-public-secondary-%s", terraform.workspace)
        },
        local.tags
    )
}

resource "aws_subnet" "private" {
    vpc_id     = aws_vpc.main.id
    availability_zone = "us-east-1b"
    cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, 100)

    tags = merge (
    {
        Name = format("i8p-private-%s", terraform.workspace)
    },
    local.tags
    )
}

resource "aws_internet_gateway" "internet" {
    vpc_id = aws_vpc.main.id

    tags = merge(
        {
            Name = format("i8p-%s", terraform.workspace)
        },
        local.tags
    )
}

# resource "aws_eip" "nat" {
#     vpc = true

#     tags = merge(
#         {
#             Name = format("i8p-%s", terraform.workspace)
#         },
#         local.tags
#     )
# }

resource "aws_route" "default-igw" {
    route_table_id = aws_vpc.main.main_route_table_id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet.id
}

resource "aws_route_table_association" "pripub" {
    subnet_id = aws_subnet.public_primary.id
    route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_route_table_association" "secpub" {
    subnet_id = aws_subnet.public_secondary.id
    route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_security_group" "ssh" {
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }

    tags = merge(
        {
            Name = format("i8p-ssh-ingress-%s", terraform.workspace)
        },
        local.tags
    )
}

resource "aws_security_group" "drupal" {
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 8000
        to_port = 8000
        cidr_blocks = [ "0.0.0.0/0" ]
        protocol = "tcp"
    }

    ingress {
        from_port = 443
        to_port = 443
        cidr_blocks = [ "0.0.0.0/0" ]
        protocol = "tcp"
    }

    tags = merge(
        {
            Name = format("i8p-drupal-ingress-%s", terraform.workspace)
        },
        local.tags
    )
}
resource "aws_security_group" "egress" {
    vpc_id = aws_vpc.main.id

    egress {
        from_port = 0
        to_port = 0
        cidr_blocks = [ "0.0.0.0/0" ]
        protocol = -1
    }

    tags = merge(
        {
            Name = format("i8p-egress-%s", terraform.workspace)
        },
        local.tags
    )
}

resource "random_shuffle" "shuffled_public_subnet_ids" {
    input = [ aws_subnet.public_primary.id, aws_subnet.public_secondary.id ]
}

resource "aws_instance" "vm" {
    ami = "ami-4bf3d731"
    key_name = "operations"
    vpc_security_group_ids = [ aws_security_group.ssh.id, aws_security_group.drupal.id, aws_security_group.egress.id ]
    instance_type = "t2.large"
    subnet_id = random_shuffle.shuffled_public_subnet_ids.result[0]

    root_block_device {
        volume_type = "gp2"
        volume_size = 15
        delete_on_termination = true
    }

    tags = merge(
        {
            Name = format("i8p-%s", terraform.workspace)
        },
        local.tags
    )
}

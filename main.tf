provider "aws" {}

terraform {
	backend "s3" {
	  bucket = "msel-ops-terraform-statefiles"
	  key = "applications/islandora"
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

data "aws_route53_zone" "zone" {
    name = var.route53_zone
}

resource "aws_vpc" "main" {
    cidr_block = "172.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = merge(
        {
            Name = format("%s-%s", var.project_prefix, terraform.workspace)
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
            Name = format("%s-public-primary-%s", var.project_prefix, terraform.workspace)
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
            Name = format("%s-public-secondary-%s", var.project_prefix, terraform.workspace)
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
        Name = format("%s-private-%s", var.project_prefix, terraform.workspace)
    },
    local.tags
    )
}

resource "aws_internet_gateway" "internet" {
    vpc_id = aws_vpc.main.id

    tags = merge(
        {
            Name = format("%s-%s", var.project_prefix, terraform.workspace)
        },
        local.tags
    )
}

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
            Name = format("%s-ssh-ingress-%s", var.project_prefix, terraform.workspace)
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
            Name = format("%s-drupal-ingress-%s", var.project_prefix, terraform.workspace)
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
            Name = format("%s-egress-%s", var.project_prefix, terraform.workspace)
        },
        local.tags
    )
}

resource "random_shuffle" "shuffled_public_subnet_ids" {
    input = [ aws_subnet.public_primary.id, aws_subnet.public_secondary.id ]
}

resource "aws_eip" "vm" {
    vpc = true
    instance = aws_instance.vm.id
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
            Name = format("%s-%s", var.project_prefix, terraform.workspace)
        },
        local.tags
    )

    # this provisioner acts as a "wait" for the playbook provisioner below.
    provisioner "remote-exec" {
        inline = ["sudo yum -y install python"]

        connection {
            type        = "ssh"
            user        = "centos"
            private_key = "${file(var.ssh_key_private)}"
            host        = "${self.public_ip}"
        }
    }

    # use ansible to blow on the new playbook.
    provisioner "local-exec" {
        command = "ANSIBLE_CONFIG='../islandora-playbook/ansible.cfg' ansible-playbook -u centos -i '${var.islandora_inv_path}' -e '@../islandora-extra-vars/extra-vars.yml' -e ansible_ssh_host='${self.public_ip}' --private-key ${var.ssh_key_private} ../islandora-playbook/playbook.yml -l default" 
    }
}

resource "aws_route53_record" "i8p" {
    zone_id = data.aws_route53_zone.zone.id
    name = format("%s.%s", var.project_prefix, var.route53_zone)
    type = "A"
    ttl = "300"
    records = [ aws_eip.vm.public_ip ]
}


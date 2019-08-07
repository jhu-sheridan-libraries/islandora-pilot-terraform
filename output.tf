output "ec2-dns" {
    value = aws_instance.vm.public_dns
}
provider "aws" {
  region = "eu-west-2"
}

resource "aws_security_group" "minikube_sg" {
  name        = "minikube-sg"
  description = "Allow SSH and Kubernetes ports"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "minikube" {
  ami             = "ami-05c172c7f0d3aed00" # Amazon Linux 2 AMI
  instance_type   = "t2.micro" # Needs to be min t2.small to work
  key_name        = "main-key" # Use your existing key pair here
  security_groups = [aws_security_group.minikube_sg.id]
  subnet_id       = "subnet-047cc7b2e82296631" # Replace with your subnet ID

user_data = <<-EOF
    #!/bin/bash
    # Update package list
    sudo apt-get update -y

    # Install Docker
    sudo apt-get install -y docker.io

    # Start Docker and enable it to start on boot
    sudo systemctl start docker
    sudo systemctl enable docker

    # Install Minikube
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/

    # Permissions
    sudo usermod -aG docker $USER
    newgrp docker
    sudo systemctl restart docker

    # Start Minikube with Docker as the driver
    minikube start --driver=docker
  EOF

  tags = {
    Name = "Minikube-Instance"
  }
}

output "minikube_public_ip" {
  value = aws_instance.minikube.public_ip
}
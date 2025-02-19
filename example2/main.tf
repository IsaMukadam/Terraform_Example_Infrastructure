provider "aws" {
  region = "us-east-1"
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

#################### MINIKUBE #####################

resource "aws_instance" "minikube" {
  ami             = "ami-0c55b159cbfafe1f0"  # Ubuntu AMI ID (replace with the appropriate one for your region)
  instance_type   = "t2.micro"
  key_name        = "main-key"  # Your existing key pair
  security_groups = [aws_security_group.minikube_sg.name]
  subnet_id       = aws_subnet.minikube_subnet.id  # Reference the subnet ID here

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

################# PROMETHEUS ######################

resource "aws_iam_role" "prometheus_role" {
  name               = "PrometheusRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "prometheus_policy" {
  name        = "PrometheusPolicy"
  description = "Permissions for Prometheus to access EC2 and CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prometheus_policy_attachment" {
  role       = aws_iam_role.prometheus_role.name
  policy_arn = aws_iam_policy.prometheus_policy.arn
}

resource "aws_iam_instance_profile" "prometheus_instance_profile" {
  name = "PrometheusInstanceProfile"
  role = aws_iam_role.prometheus_role.name
}

# EC2 Instance for Prometheus
resource "aws_instance" "prometheus" {
  ami                    = "ami-05c172c7f0d3aed00" # Ubuntu AMI in EU West (London)
  instance_type          = "t2.micro"
  key_name               = "main-key" # Replace with your key name
  subnet_id              = aws_subnet.web_subnet_1.id
  iam_instance_profile   = aws_iam_instance_profile.prometheus_instance_profile.name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y

    # Install Prometheus
    sudo apt-get install -y prometheus

    # Create Prometheus configuration
    cat <<EOT > /etc/prometheus/prometheus.yml
    global:
      scrape_interval: 15s

    scrape_configs:
      # Scraping Apache Exporter
      - job_name: 'apache'
        static_configs:
          - targets: ['${aws_instance.apache_exporter.private_ip}:9117']  # Replace with Apache Exporter endpoint
          
      # Scraping EC2 instance metrics (optional)
      - job_name: 'ec2'
        ec2_sd_configs:
          - region: "eu-west-2"
        relabel_configs:
          - source_labels: [__meta_ec2_instance_id]
            target_label: instance
          - source_labels: [__meta_ec2_instance_private_ip]
            target_label: instance_ip
    EOT

    # Start Prometheus
    sudo systemctl restart prometheus
    sudo systemctl enable prometheus
  EOF

  tags = {
    Name = "Prometheus-Server"
  }
}


# EC2 Instance for Apache and Apache Exporter
resource "aws_instance" "apache_exporter" {
  ami                    = "ami-05c172c7f0d3aed00"  # Replace with the appropriate AMI for your region
  instance_type          = "t2.micro"  # Adjust the instance type as needed
  key_name               = "main-key"  # Replace with your key name
  subnet_id              = aws_subnet.web_subnet_1.id  # Replace with the appropriate subnet ID
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  # Install Apache and Apache Exporter on the EC2 instance
  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y

    # Install Apache
    sudo apt-get install -y apache2

    # Install Apache Exporter
    sudo apt-get install -y wget
    wget https://github.com/prometheus/apache_exporter/releases/download/v0.11.0/apache_exporter-0.11.0.linux-amd64.tar.gz
    tar xvf apache_exporter-0.11.0.linux-amd64.tar.gz
    mv apache_exporter-0.11.0.linux-amd64/apache_exporter /usr/local/bin/

    # Run Apache Exporter (assuming Apache is running on the server)
    nohup /usr/local/bin/apache_exporter &
  EOF

  tags = {
    Name = "Apache-and-Apache-Exporter"
  }
}


# EC2 Instance for CloudWatch Exporter (just an example)
resource "aws_instance" "cloudwatch_exporter" {
  ami                    = "ami-05c172c7f0d3aed00" # Ubuntu AMI in EU West (London)
  instance_type          = "t2.micro"
  key_name               = "main-key" # Replace with your key name
  subnet_id              = aws_subnet.web_subnet_1.id
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y

    # Install CloudWatch Exporter
    wget https://github.com/prometheus/cloudwatch_exporter/releases/download/0.12.0/cloudwatch_exporter-0.12.0.jar
    sudo mv cloudwatch_exporter-0.12.0.jar /usr/local/bin/cloudwatch_exporter.jar

    # Start CloudWatch Exporter
    nohup java -jar /usr/local/bin/cloudwatch_exporter.jar 9106 &
  EOF

  tags = {
    Name = "CloudWatch-Exporter"
  }
}


####################### GRAFANA ###########################

# EC2 Instance for Grafana
resource "aws_instance" "grafana" {
  ami                    = "ami-05c172c7f0d3aed00" # Ubuntu AMI in EU West (London)
  instance_type          = "t2.micro"
  key_name               = "main-key" # Replace with your key name
  subnet_id              = aws_subnet.web_subnet_1.id
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y

    # Install Grafana
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
    sudo apt-get update
    sudo apt-get install grafana

    # Start Grafana
    sudo systemctl start grafana-server
    sudo systemctl enable grafana-server

    # Wait for Grafana to start
    sleep 10

    # Set up Prometheus as data source in Grafana
    curl -X POST -H "Content-Type: application/json" -d '{
      "name": "Prometheus",
      "type": "prometheus",
      "url": "http://${aws_instance.prometheus.private_ip}:9090",  # Reference Prometheus private IP dynamically
      "access": "proxy"
    }' http://admin:admin@localhost:3000/api/datasources
  EOF

  tags = {
    Name = "Grafana-Server"
  }
}

########################### TERRAFORM STATE BUCKET #########################

# S3 Bucket to store Terraform state (if not already created)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-terraform-state-bucket"  # Replace with your bucket name
  acl    = "private"                    # Default ACL
}

# Terraform backend configuration to use S3 for state storage
terraform {
  backend "s3" {
    bucket = "my-terraform-state-bucket"  # Replace with your bucket name
    key    = "terraform/state.tfstate"    # Path within the bucket where state is stored
    region = "eu-west-2"                  # Replace with your AWS region
  }
}









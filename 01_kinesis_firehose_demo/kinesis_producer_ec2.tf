provider "aws" {
  region  = "us-east-1"
  profile = "iamadmin"
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "ssh_only" {
  name   = "ssh_only"
  vpc_id = aws_default_vpc.default.id

  ingress {
    description = "ssh from any ip"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "all traffic to outside"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Get the latest aws linux ami 
data "aws_ami" "amazon_linux" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["137112412989"] # Amazon
}


# Create an ec2 instance that curls an api every sec to generate randome user data and dump it into json files . 
# These json files will be used as stream data 

resource "aws_instance" "kinesis_producer_ec2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  tags = {
    Name = "kinesis_producer_ec2"
  }
  key_name = "psb-win"

  user_data = <<-EOF
  #!/bin/bash
  yum update -y 

  # Setup kinesis agent on this server
  yum install -y aws-kinesis-agent
  
  # Configure agent.json to send stream to firehose service
  # filePattern will provide all files . 
  # deliveryStream is the kinesis firehose delivery stream name 

  mv /etc/aws-kinesis/agent.json /etc/aws-kinesis/agent_bkp.json
  mkdir /var/log/kinesis_stream_data

  {
     echo '  {                                                                      '
     echo '    "cloudwatch.emitMetrics": true,                                      '
     echo '    "kinesis.endpoint": "",                                              '
     echo '    "firehose.endpoint": "firehose.us-east-1.amazonaws.com",             '
     echo '                                                                         '
     echo '    "flows": [                                                           '
     echo '      {                                                                  '
     echo '        "filePattern": "/var/log/kinesis_stream_data/stream_data.json",  '
     echo '        "deliveryStream": "psb_kinesis_firehose_delivery_stream"        '
     echo '      }                                                                  '
     echo '    ]                                                                    '
     echo '  }                                                                      '
  } >> /etc/aws-kinesis/agent.json

  # start the kinesis agent
  service aws-kinesis-agent start 

  # enable start at boot
  chkconfig aws-kinesis-agent on

  # Create dir for stream data and generate stream data . Append a new record after each second to the file . 
  while true; do echo $(curl https://randomuser.me/api/) >> "/var/log/kinesis_stream_data/stream_data.json"; done
  EOF

  vpc_security_group_ids = [aws_security_group.ssh_only.id]
  iam_instance_profile   = "${aws_iam_instance_profile.instance_profile_for_kinesis.name}"

}

## Need to attach IAM role since we dont want to embedd long term credentials in it to access kinesis

# Create an iam role to give ec2 service access to all services 
resource "aws_iam_role" "ec2-assume-role" {
  name = "ec2-assume-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "adminaccess-policy" {
  name        = "adminaccess-policy"
  description = "Full access to kinesis"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach-access-to-kinesis-policy-to-ec2-assume-role" {
  role       = aws_iam_role.ec2-assume-role.name
  policy_arn = aws_iam_policy.adminaccess-policy.arn
}


resource "aws_iam_instance_profile" "instance_profile_for_kinesis" {                             
  name  = "instance_profile_for_kinesis" 
  role = "${aws_iam_role.ec2-assume-role.name}"
} 


output "instance_id" {
  description = "Public ip of the EC2 instance"
  value       = aws_instance.kinesis_producer_ec2.public_ip
}

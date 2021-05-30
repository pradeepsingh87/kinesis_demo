# Create a s3 bucket for the firehose to dump the stream data. 
resource "aws_s3_bucket" "kinesis-stream-data" {
  bucket = "kinesis-stream-data"
  acl    = "private"
  force_destroy = true
  lifecycle {
    prevent_destroy = false
  }
  
}

# Create an iam role to give firehose service access to all services 
resource "aws_iam_role" "firehose_role" {
  name = "firehose_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create a kineis firehose delivery stream 
resource "aws_kinesis_firehose_delivery_stream" "psb_kinesis_firehose_delivery_stream" {
  name        = "psb_kinesis_firehose_delivery_stream"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.kinesis-stream-data.arn
    buffer_size        = 5  # file size will be 5 mb
    buffer_interval    = 60 # firehose will collect stream data for 60 sec before writing it to buffer.
    # compression_format = "GZIP"

  }
}

resource "aws_iam_role_policy_attachment" "attach-access-to-firehose_role" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.adminaccess-policy.arn
}


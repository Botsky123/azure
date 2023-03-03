provider "aws" {

  region = var.region
  access_key = var.access_key
  secret_key = var.secret_key

}

resource "aws_s3_bucket" "terraform_state_s3" {
  bucket = "tfstate" 
  force_destroy = true
  versioning {
     	enabled = true
    	}
  server_side_encryption_configuration {
	rule {
  	apply_server_side_encryption_by_default {
    	sse_algorithm = "AES256"
  	}
	}
  }
}


resource "aws_dynamodb_table" "terraform_locks" {
  name     	= "test-db"
  billing_mode = "PAY_PER_REQUEST"
  hash_key 	= "LockID"
    	attribute {
     	name = "LockID"
     	type = "S"
  	}
}

terraform {
  backend "s3" {
	bucket     	= "tfstate"
	key        	= "terraform.tfstate"
	region     	= var.region
	dynamodb_table = "test-db"
	encrypt    	= true
	}
}

resource "aws_iam_policy" "bucket_policy" {
  name        = "test-bucket-policy"
  path        = "/"
  description = "Allow "

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::example/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "test_role" {
  name = "test_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "test_bucket_policy" {
  role       = aws_iam_role.test_role.name
  policy_arn = aws_iam_policy.bucket_policy.arn
}

resource "aws_s3_bucket" "example" {
  bucket = "example"
  force_destroy = false
  versioning {
    enabled = true
  }
  logging {
    enabled = false
  }

  tags = {
    Name        = "secure-bucket"
    Environment = "Dev"
  }

}

resource "aws_iam_role" "replication" {
  name = "test"

  assume_role_policy = POLICY(
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
})
}

resource "aws_iam_policy" "replication" {
  name = "test_policy"

  policy = POLICY(
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.example.arn}"
      ]
    }
]
})
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

resource "aws_s3_bucket" "destination" {
  bucket = "test-dest"
  logging {
    enabled = false
  }
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.central
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.source]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.example.id

  rule {
    id = "foobar"

    filter {
      prefix = "foo"
    }

    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD"
    }
  }
}

resource "aws_kms_key" "mykey" {
  description             = "KMS key 1"
  enable_key_rotation = true
  deletion_window_in_days = 10
}

resource "aws_s3_bucket_server_side_encryption_configuration" "test" {
  bucket = ["aws_s3_bucket.example.bucket","aws_s3_bucket.destination.bucket"]

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mykey.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = ["aws_s3_bucket.example.id","aws_s3_bucket.destination.id"]
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

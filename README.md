
# Terraform AWS Final Exam – 

This repository is intentionally **broken**. Your job is to fix it and complete the staging deployment.

## What you must deploy
- VPC with 2 public + 2 private subnets across 2 Availabilty Zones, Internet Gateway, 
**NAT** for private egress, correct routes
- ALB in public subnets forwarding to EC2 instances 
- S3 bucket with versioning (name must be unique, passed via variable)
- RDS Postgres in private subnets (no public access)
- CloudWatch alarm on EC2 CPU > 75% 
- GitHub Actions CI: fmt, validate on PR; plan on PR; apply on main

## Constraints
- Edit only existing files if possible.
- Use naming format: `<studentname>-<studentnumber>-<resource>-staging`.
- Use functions like `cidrsubnet()` and for_each/count where appropriate.


Good luck. You have 2 hours.

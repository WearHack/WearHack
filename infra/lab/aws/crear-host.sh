#!/bin/bash
# Corre en CloudShell, desde la carpeta infra/lab/aws. Crea security group, EC2 e IP
# elastica. Reusa el SG, la instancia "wearhack-core" y la IP si ya existen.
#
# Antes: secretos.sh (URIs de Atlas y token de GitHub en SSM) y cognito.sh.
set -euo pipefail
cd "$(dirname "$0")"

VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=wearhack-core Name=vpc-id,Values="$VPC" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG" = "None" ]; then
  # Solo 80 y 443. Sin 22: se entra por SSM.
  SG=$(aws ec2 create-security-group --group-name wearhack-core --description "WearHack Core HTTP y HTTPS" \
    --vpc-id "$VPC" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG" --ip-permissions \
    'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' \
    'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' >/dev/null
fi

ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=wearhack-core \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$ID" = "None" ]; then
  AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query Parameter.Value --output text)
  ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.large \
    --iam-instance-profile Name=LabInstanceProfile --security-group-ids "$SG" \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=30,VolumeType=gp3}' \
    --metadata-options HttpTokens=required --user-data file://instalar-host.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wearhack-core}]' \
    --query 'Instances[0].InstanceId' --output text)
fi
aws ec2 wait instance-running --instance-ids "$ID"

ALLOC=$(aws ec2 describe-addresses --filters Name=tag:Name,Values=wearhack-core \
  --query 'Addresses[0].AllocationId' --output text)
if [ "$ALLOC" = "None" ]; then
  ALLOC=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=wearhack-core}]' \
    --query AllocationId --output text)
fi
aws ec2 associate-address --instance-id "$ID" --allocation-id "$ALLOC" >/dev/null
IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC" --query 'Addresses[0].PublicIp' --output text)
echo "LISTO ID=$ID IP=$IP DOMINIO=$(echo "$IP" | tr . -).sslip.io"

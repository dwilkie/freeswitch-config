# freeswitch-config

Freeswitch configuration optimized for [mod_rayo](https://freeswitch.org/confluence/display/FREESWITCH/mod_rayo) and [Adhearsion](https://github.com/adhearsion/adhearsion).

## Deployment

### Elastic Beanstalk

This configuration is optimized for deployment on a Amazon Elastic Beanstalk multicontainer docker instance. To deploy this to your own AWS account create an Elastic Beanstalk application and follow the instructions below.

#### Create a VPC

Create a VPC with 2 public subnets (one for each availability zone)

#### Create a new Elastic Beanstalk Application

Create an Multi-Container Docker Elastic Beanstalk single instance application under your VPC. This will give you an Elastic IP address which won't change if you terminate or scale your instances. When prompted for the VPC details enter the VPC and subnets you created above. The following commands are useful.

```
$ eb platform select
$ eb create --vpc -i t2.micro --single
```

#### Configure a S3 bucket to any sensitive or custom configuration

Adapted from [this blog post](https://blogs.aws.amazon.com/security/post/Tx2B3QUWAA7KOU/How-to-Manage-Secrets-for-Amazon-EC2-Container-Service-Based-Applications-by-Usi)

Sensitive freeswitch configuration can be stored on S3. When the docker container runs the [docker-entrypoint.sh](https://github.com/dwilkie/freeswitch-config/blob/master/docker-entrypoint.sh) it downloads the configuration before starting freeswitch.

In order for this to work you need to set up an S3 bucket in your AWS account in which to store the configuration and restrict the access to the VPC.

First, create a bucket in S3 using the AWS web console in which to store your configuration.

Next, create a VPC Endpoint to S3. Use the following command following command replacing `<your-aws-profile>` with your configured profile in `~/.aws/credentials`, `VPC_ID` and `ROUTE_TABLE_ID` with the values found in your VPC configuration via the AWS web console and `REGION` with the name of your region e.g. `ap-southeast-1`

```
$ aws ec2 --profile <your-aws-profile> create-vpc-endpoint --vpc-id VPC_ID --route-table-ids ROUTE_TABLE_ID --service-name com.amazonaws.REGION.s3 --region REGION
```

You should see the output similar to the following:

```json
{
  "VpcEndpoint": {
  "PolicyDocument": "{\"Version\":\"2008-10-17\",\"Statement\":[{\"Sid\":\"\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":
\"*\",\"Resource\":\"*\"}]}",
  "VpcId": "vpc-1a2b3c4d",
  "State": "available",
  "ServiceName": "com.amazonaws.us-east-1.s3",
  "RouteTableIds": [
    "rtb-11aa22bb"
  ],
  "VpcEndpointId": "vpce-3ecf2a57",
  "CreationTimestamp": "2016-05-15T09:40:50Z"
  }
}
```

Take note of the `VpcEndpointId` which is required for the next step.

Next, create a file called `policy.json` with the following contents replacing `SECRETS_BUCKET_NAME` with your the name of your new bucket and `VPC_ID` with the `VpcEndpointId` from the previous step.

This policy prevents unencrypted uploads and restricts access to the bucket to the VPC.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnEncryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::SECRETS_BUCKET_NAME/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    },
    {
      "Sid": " DenyUnEncryptedInflightOperations",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::SECRETS_BUCKET_NAME/*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": false
        }
      }
    },
    {
      "Sid": "Access-to-specific-VPCE-only",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [ "s3:GetObject", "s3:PutObject", "s3:DeleteObject" ],
      "Resource": "arn:aws:s3:::SECRETS_BUCKET_NAME/*",
      "Condition": {
        "StringNotEquals": {
          "aws:sourceVpce": "VPC_ID"
        }
      }
    }
  ]
}
```

Next, add the policy to the bucket. Use the following command replacing `SECRETS_BUCKET_NAME` with the name of your bucket.

```
$ aws s3api put-bucket-policy --profile <your-aws-profile> --bucket SECRETS_BUCKET_NAME --policy file:////home/user/path/to/policy.json
```

You can check that your policy was uploaded successfully with the following command.

```
$ aws s3api get-bucket-policy --profile <your-aws-profile> --bucket SECRETS_BUCKET_NAME
```

Next, allow your Elastic Beanstalk Instances to access S3. Using the AWS web console, navigate to IAM roles and add a policy to the role `aws-elasticbeanstalk-ec2-role` to allow Amazon S3 Full Access.

Finally, upload your sensitive configuration to S3 from your EC2 Instance. Note you cannot do this from your development machine because we have already resticted access to the VPC.

```
$ aws s3 cp freeswitch_conf_dir s3://SECRETS_BUCKET_NAME/FREESWITCH_CONF_DIR --sse
```

When updating configuration, download your custom configuration from S3, update it, reupload it to S3 and re-deploy the application. The following commands are useful:

```
$ aws s3 cp s3://${SECRETS_BUCKET_NAME}/FREESWITCH_CONF_DIR .
$ aws s3 cp freeswitch_conf_dir s3://SECRETS_BUCKET_NAME/FREESWITCH_CONF_DIR --sse
```

#### Dockerrun.aws.json

[Dockerrun.aws.json](https://github.com/dwilkie/freeswitch-config/blob/master/Dockerrun.aws.json) contains the container configuration for FreeSwitch. It's options are passed to the `docker run` command.

##### Memory

You must specify the memory option in this file. To set it to the maximum value possible, first set it to a number exceeding the memory of the host instance. Then grep the logs in `/var/log/eb-ecs-mgr.log` and look for `remainingResources`. Look for the `MEMORY` value and use this in your `Dockerrun.aws.json` file.

##### RTP Port Mappings

The script `./bin/open_rtp_ports.rb`, adds RTP port mappings to `Dockerrun.aws.json`.

#### Security Groups and Networking

[Dockerrun.aws.json](https://github.com/dwilkie/freeswitch-config/blob/master/Dockerrun.aws.json) defines a list of port mappings which map the host to the docker container. Not all of these ports need to be opened in your security group. For example port 8021 is used for `mod_event_socket` but this port should not be opened on in your security group. Depending on your application you may need to open the following ports in your security group:

    udp     16384:32768  (RTP)
    udp     5060         (SIP)
    tcp     5222         (XMPP / Adhearsion)

It's highly recommended that you restrict the source of the ports in your security group. For example for SIP and RTP traffic restric the ports to the known SIP provider / telco. For XMPP / Adhearsion you can restrict the port to instances inside the your VPC.

#### FreeSwitch CLI

In order to access the FreeSwitch CLI ssh into your instance, run the docker container which contains FreeSwitch in interactive mode with `/bin/bash`, then from within the container, run the `fs_cli` command specifying the host and password parameters. The host can be found by inspecting the running freeswitch instance's container.

The following commands are useful.

```
$ sudo docker ps
$ sudo docker inspect <process_id>
$ sudo docker run -i -t dwilkie/freeswitch-rayo /bin/bash
$ fs_cli -H FREESWITCH_HOST -p EVENT_SOCKET_PASSWORD
```

##### Useful CLI Commands

Reload SIP Profiles

```
sofia profile external [rescan|reload]
```

Turn on siptrace

```
sofia global siptrace on
```

#### Troubleshooting

If the app fails to deploy the following logs are useful:

* `/var/log/eb-ecs-mgr.log`
* `/var/log/eb-activity.log`

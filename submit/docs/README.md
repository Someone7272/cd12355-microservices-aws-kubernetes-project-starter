# Coworking space service

A microservices-based application that provides one-time access tokens.
The access tokens are then used to authorize user entry to a Coworking office space.

## Prerequisites

Before you can deploy the application, set up the prerequisites.

- A Git repository similar to this one
- AWS account with administrator access
- Linux OS with these applications installed:
    - AWS CLI v2
    - eksctl
    - kubectl

## Pre-deployment

Before you start deployment, configure the environment.

1. Clone this repository.
2. Configure your AWS CLI credentials.
3. Ensure your command line location is the repository root.

## Create the EKS cluster

The EKS cluster will be used to host the microservices application and database instance.
You can change the cluster name, region and nodegroup name to suit your individual requirements.
Also, you can change the node type. However, during testing, no more than 20% CPU usage and 50% memory usage was observed.
Therefore, the smallest instance type has been selected to be cost effective. If more processing power is required, you can increase the minimum and maximum nodes.

`eksctl create cluster --name my-cluster --region us-east-1 --nodegroup-name my-nodes --node-type t3.small --nodes 1 --nodes-min 1 --nodes-max 2`

Cluster creation may take a while. Once it completes, set your AWS CLI to use this cluster's configuration.
Replace the region and cluster name if required.

`aws eks --region us-east-1 update-kubeconfig --name my-cluster`

## Deploy the database services

The PostgreSQL instance is hosted on EKS. Included in the Git repository are deployment manifests.
First, we need to check the storage class of the EKS instance.

`kubectl get storageclass`

Then in the Git repository, check the `pv.yaml` file. The `storageClassName` must match the output of `kubectl get storageclass`.

Open `postgresql-deployment.yaml`. You can change the `POSTGRES_DB`, `POSTGRES_USER` and `POSTGRES_PASSWORD` values as required.

Once you're done, you can apply the deployment manifests to the cluster.

`kubectl apply -f pvc.yaml`
`kubectl apply -f pv.yaml`
`kubectl apply -f postgresql-deployment.yaml`
`kubectl apply -f postgresql-service.yaml`

Connect to the database to set up the database structure. We can use kubectl port forwarding for this.

`kubectl port-forward service/postgresql-service 5433:5432 &`

After you've done that, install PostgreSQL components on your local environment.

`apt update`
`apt install postgresql postgresql-contrib`

Set your database password that you configured in `postgresql-deployment.yaml` as an environment variable.
Replace the example value with the password you chose.

`export DB_PASSWORD=mypassword`

To create the sample table structure and insert the sample data into the database, use these commands.
Replace myuser and mydatabase with the username and database name you chose in `postgresql-deployment.yaml`.

`PGPASSWORD="$DB_PASSWORD" psql --host 127.0.0.1 -U myuser -d mydatabase -p 5433 < db/<FILE_NAME.sql>`

Once you have finished setting up your database, you can close the forwarded port.

`ps aux | grep 'kubectl port-forward' | grep -v grep | awk '{print $2}' | xargs -r kill`

## Create an AWS Elastic Container Registry repository

The Docker images will be pushed to an ECR repository once built.
Using the AWS web console, create a private ECR repository. Ensure that tag immutability is disabled.

## Create an AWS CodeBuild project

CodeBuild provides CI/CD functionality. When code is committed to your Git repository, CodeBuild can automatically build a new Docker image and push it to AWS ECR.
Using the AWS web console, create a new CodeBuild project. When creating the project, use these settings:

- The primary source should be configured to use your Git provider
- The OS must be Amazon Linux 2 x86_64
- Ensure that **Rebuild every time a code change is pushed to this repository** is selected
- In Environment Additional Configuration, ensure that the Privileged is selected
- In Environment Additional Configuration, ensure that these environment variables are set:
    - AWS_DEFAULT_REGION
        - Your AWS default region name
    - AWS_ACCOUNT_ID
        - Your AWS account ID (numbers only)
    - IMAGE_REPO_NAME
        - The name of your AWS ECR repository
- Ensure that **Use a buildspec file** is selected in the Buildspec section

Now when you push any changes to the Git repository, AWS CodeBuild will build a new Docker image and push it to your AWS ECR repository.

## Customize the deployment

In the deployment folder, there are `configmap.yaml`, `coworking.yaml` and `secrets.yaml` files. You need to ensure that the values in them are correct for your environment.

### Configmap

- DB_NAME
    - The name of your database that you set originally in the `postgresql-deployment.yaml` file.
- DB_HOST
    - IPv4 or DNS name of the PostgreSQL database service. You can run `kubectl get svc` to find the cluster IP of the database service.
- DB_PORT
    - Port the database service is running on. By default, this should be 5432, however if you changed it in the `postgresql-deployment.yaml` file, make sure this is reflected here.

### Coworking

- image
    - Change this value to your AWS ECR URL. Here is an example value, you can replace the placeholder values with your own:
        - [AWS ACCOUNT ID].dkr.ecr.[AWS REGION].amazonaws.com/[ECR REPO NAME]:latest

### Secrets

- Secrets are base64 encoded. You can generate base64 output using `echo -n [VALUE]`
- DB_USERNAME and DB_PASSWORD
    - Change these to the values you used in the `postgresql-deployment.yaml` file. Ensure that the values are base64 encoded.

## Deploy the microservices application

You can apply everything inside the deployment folder to the cluster.

`kubectl apply -f deployment/`

## Test the microservies application

Test the application using a HTTP get request.
Run `kubectl get svc` again. The microservices application will have an external address. Use this to test the application.

`curl [EXTERNAL ADDRESS]:[5153]/api/reports/daily_usage`
`curl [EXTERNAL ADDRESS]:[5153]/api/reports/user_visits`

Both of these requests should respond with JSON. If an error is returned, check the basic troubleshooting section further down this page.

## Set up CloudWatch Container Insights

Container Insights can help with more in-depth troubleshooting where required. It can give information about the application logs, the performace and load on the hardware and other events.

### Set up the IAM permissions

In the AWS web console, go to AWS Elastic Kubernetes Service. Select the cluster you're using, and in the Compute tab, select the node group.
You will see the Node IAM role ARN. Click this to see the role in the IAM console. Take note of the role name (not the ARN).

Then you can use this command to update the IAM role policy.

`aws iam attach-role-policy --role-name [NODE GROUP ROLE NAME] --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`

### Add the CloudWatch Container Insights add-on to the cluster

Use this command to install the add-on to your cluster

`aws eks create-addon --addon-name amazon-cloudwatch-observability --cluster-name [NAME OF YOUR CLUSTER]`

In a few minutes, Container Insights should become available in CloudWatch.

## Basic troubleshooting

There are some commands which can help find out if the microservices application is working correctly.

`kubectl get svc`

- Use this to check if the services have been created successfully

`kubectl get deployments`

- This wil show if any pods that are part of the deployment failed to start. Check the READY status for the deployments.

`kubectl get pods`

- Shows all provisioned containers. If any of them have failed, this is shown in the READY status for the pods.

`kubectl describe pod [POD NAME]`

- Shows the major events of the pod's lifetime. It can help determine what stage any issues occured.

`kubectl logs [PODNAME]`

- Outputs the application logs. This is for more advanced troubleshooting.
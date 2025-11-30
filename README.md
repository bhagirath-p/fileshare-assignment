# FileShare Terraform deployment

1. Install Terraform and AWS CLI and configure credentials.
2. Put these files in a folder.
3. Create a subfolder `lambda/` and add `presign_lambda.py`.
4. Run:
   - `terraform init`
   - `terraform plan`
   - `terraform apply`
5. After apply, check outputs for bucket names, API endpoint and CloudFront domain.
6. The above script will create an application setup as shown below
 
![](AWS%20File%20Sharing%20System%20Flowchart.png)

> NOTE: This example uses minimal auth on API Gateway (NONE). Hook Cognito authorizer to the API Gateway for production JWT validation.

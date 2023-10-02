#! /bin/bash
#########################################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.                    #
# SPDX-License-Identifier: MIT-0                                                        #
#                                                                                       #
# Permission is hereby granted, free of charge, to any person obtaining a copy of this  #
# software and associated documentation files (the "Software"), to deal in the Software #
# without restriction, including without limitation the rights to use, copy, modify,    #
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to    #
# permit persons to whom the Software is furnished to do so.                            #
#                                                                                       #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,   #
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A         #
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT    #
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION     #
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE        #
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                                #
#########################################################################################

region=$1
bucket_owner=$2
service_catalog_principal_name=$3

if [ -z $region ] || [ -z $bucket_owner ]
then
    echo "You must provide a region and bucket owner as positional parameters"
    exit
else
    echo "The region you provided is: $region"
    echo "The bucket owner you provided is: $bucket_owner"
fi

account_id=$(aws sts get-caller-identity | jq -r .'Account')
echo "This is the account ID: $account_id"

organization_id=$(aws organizations describe-organization | jq -r '.Organization''.Id')
echo "This is the AWS Organization ID: $organization_id"

## Create the S3 Bucket

aws cloudformation create-stack \
--stack-name Service-Catalog-Product-S3 \
--template-body file://service-catalog/s3-service-catalog-product.yml \
--parameters \
ParameterKey="pAWSOrganizationId",ParameterValue=$organization_id \
ParameterKey="pBucketOnwer",ParameterValue=$bucket_owner \
--region $region

## Fetch the bucket name
bucket_name=$(aws cloudformation describe-stacks --stack-name Service-Catalog-Product-S3 --region $region --query 'Stacks[0].Outputs[?OutputKey==`oBucketName`].OutputValue' --output text)

iter=true
while [[ $iter ]]
do
    if [[ $bucket_name == "None" ]]; then 
        echo "S3 CloudFormation Stack not created yet, waiting..."
        sleep 2
        bucket_name=$(aws cloudformation describe-stacks --stack-name Service-Catalog-Product-S3 --region $region --query 'Stacks[0].Outputs[?OutputKey==`oBucketName`].OutputValue' --output text)
        stack_status=$(aws cloudformation describe-stacks --stack-name Service-Catalog-Product-S3 --region $region --query 'Stacks[0].StackStatus' --output text)
        if [[ $stack_status == *"ROLLBACK"* ]] || [[ $stack_status == *"FAILED"* ]]; then
            echo "The Service Catalog CloudFormation Stack Creation Process Failed, Exiting..."
            exit
        fi
    else
        echo "Stack Created!"
        break
    fi
done

echo "The bucket you created is named: $bucket_name"

## Package Templates and upload to S3
echo "Packaging the MGN main template"
cd mgn
pwd
mgn_packaged_template=aws-mgn-main-pkgd.yml
mgn_object=aws-mgn-main.yml
aws cloudformation package --template-file aws-mgn-main.yml --s3-bucket $bucket_name --output-template-file $mgn_packaged_template --force-upload
aws s3 cp $mgn_packaged_template s3://$bucket_name/$mgn_object

echo "Packaging the DRS main template"
cd ../drs
pwd
drs_packaged_template=aws-drs-main-pkgd.yml
drs_object=aws-drs-main.yml
aws cloudformation package --template-file aws-drs-main.yml --s3-bucket $bucket_name --output-template-file $drs_packaged_template --force-upload
aws s3 cp $drs_packaged_template s3://$bucket_name/$drs_object

## Build Object URLs
mgn_object_url=https://$bucket_name.s3.amazonaws.com/$mgn_object
echo "The MGN main template object URL is: $mgn_object_url"
drs_object_url=https://$bucket_name.s3.amazonaws.com/$drs_object
echo "The DRS main template object URL is: $drs_object_url"

## Deploy IAM roles template
cd ..

## Check for existing roles

mgn_drs_sc_lc_role=$(aws iam get-role --role-name MGNDRSServiceCatalogLaunchConstraintRole)
sc_user_role=$(aws iam get-role --role-name ServiceCatalogEndUserRole)

if [ -z $mgn_drs_sc_lc_role ] && [ -z $sc_user_role ]
then
    echo "IAM Roles for Service Catalog Launch Constraint and Service Catalog User do not exist... Creating."
    aws cloudformation create-stack \
    --stack-name IAM-Service-Catalog-Launch-Constraint \
    --template-body file://service-catalog/iam-roles-service-catalog.yml \
    --parameters \
    ParameterKey="pSCEndUserRoleName",ParameterValue=$service_catalog_principal_name \
    --region $region \
    --capabilities "CAPABILITY_NAMED_IAM"

    sc_enduser_role_arn=$(aws cloudformation describe-stacks --stack-name IAM-Service-Catalog-Launch-Constraint --region $region --query 'Stacks[0].Outputs[?OutputKey==`oServiceCatalogEndUserRole`].OutputValue' --output text)
    iter=true
    while [[ $iter ]]
    do
        if [[ $sc_enduser_role_arn == "None" ]]; then 
            echo "IAM CloudFormation Stack not created yet, waiting..."
            sleep 2
            sc_enduser_role_arn=$(aws cloudformation describe-stacks --stack-name IAM-Service-Catalog-Launch-Constraint --region $region --query 'Stacks[0].Outputs[?OutputKey==`oServiceCatalogEndUserRole`].OutputValue' --output text)
            stack_status=$(aws cloudformation describe-stacks --stack-name IAM-Service-Catalog-Launch-Constraint --region $region --query 'Stacks[0].StackStatus' --output text)
            if [[ $stack_status == *"ROLLBACK"* ]] || [[ $stack_status == *"FAILED"* ]]; then
                echo "The Service Catalog CloudFormation Stack Creation Process Failed, Exiting..."
                exit
            fi
        else
            echo "Stack Created!"
            break
        fi
    done
else
    echo "One or both of the IAM Roles for Service Catalog Launch Constraint and Service Catalog User exist... Validate that both exist after the solution finishes deploying."
fi

aws cloudformation create-stack \
--stack-name MGN-DRS-Init-Service-Catalog \
--template-body file://service-catalog/aws-service-catalog.yml \
--parameters \
ParameterKey="pAcceptLanguage",ParameterValue="en" \
ParameterKey="pPortfolioDescription",ParameterValue="Service Catalog Portfolio for AWS Application Migration Service (MGN) and Elastic Disaster Recovery (DRS) Service Initilization Automation." \
ParameterKey="pDisplayName",ParameterValue="MGN-DRS-Init" \
ParameterKey="pPortfolioOwner",ParameterValue="CloudPlatformTeam" \
ParameterKey="pPortfolioCategory",ParameterValue="Migration" \
ParameterKey="pLaunchConstraintLocalRoleName",ParameterValue="MGNDRSServiceCatalogLaunchConstraintRole" \
ParameterKey="pProductDistributor",ParameterValue="Migration" \
ParameterKey="pProductOwner",ParameterValue="CloudPlatformTeam" \
ParameterKey="pMGNTemplateS3Url",ParameterValue=$mgn_object_url \
ParameterKey="pDRSTemplateS3Url",ParameterValue=$drs_object_url \
ParameterKey="pOrganizationId",ParameterValue=$organization_id \
--capabilities "CAPABILITY_NAMED_IAM" \
--region $region

# Associate a Principal with the Portfolio

## Fetch the Portfolio ID
portfolio_id=$(aws cloudformation describe-stacks --stack-name MGN-DRS-Init-Service-Catalog --region $region --query 'Stacks[0].Outputs[?OutputKey==`oMGNDRSInitPortfolioId`].OutputValue' --output text)

iter=true
while [[ $iter ]]
do
    if [[ $portfolio_id == "None" ]]; then 
        echo "Service Catalog CloudFormation Stack not created yet, waiting..."
        sleep 2
        portfolio_id=$(aws cloudformation describe-stacks --stack-name MGN-DRS-Init-Service-Catalog --region $region --query 'Stacks[0].Outputs[?OutputKey==`oMGNDRSInitPortfolioId`].OutputValue' --output text)
        stack_status=$(aws cloudformation describe-stacks --stack-name MGN-DRS-Init-Service-Catalog --region $region --query 'Stacks[0].StackStatus' --output text)
        if [[ $stack_status == *"ROLLBACK"* ]] || [[ $stack_status == *"FAILED"* ]]; then
            echo "The Service Catalog CloudFormation Stack Creation Process Failed, Exiting..."
            exit
        fi
    else
        echo "Stack Created!"
        break
    fi
done

echo "Associating principal with the Portfolio"

principal_arn="arn:aws:iam:::role/$service_catalog_principal_name"

aws servicecatalog associate-principal-with-portfolio \
--portfolio-id $portfolio_id \
--principal-arn $principal_arn \
--principal-type IAM_PATTERN \
--region $region

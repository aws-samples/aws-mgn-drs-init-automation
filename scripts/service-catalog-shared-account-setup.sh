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

if [ -z $region ]
then
    echo "You must provide a region in the positional parameter"
    exit
else
    echo "The region you provided is: $region"
fi

## Create the Service Catalog Product Launch Contraint Role and Service Catalog User Role

echo "Checking for the required roles..."
mgn_drs_sc_lc_role=$(aws iam get-role --role-name MGNDRSServiceCatalogLaunchConstraintRole)
sc_user_role=$(aws iam get-role --role-name ServiceCatalogEndUserRole)

if [ -z $mgn_drs_sc_lc_role ] && [ -z $sc_user_role ]
then
    echo "Role creation required, creating the roles now"
    aws cloudformation create-stack \
    --stack-name IAM-Service-Catalog-Launch-Constraint \
    --template-body file://service-catalog/iam-roles-service-catalog.yml \
    --region $region \
    --disable-rollback \
    --capabilities "CAPABILITY_NAMED_IAM"
else
    echo "One or both of the IAM Roles for Service Catalog Launch Constraint and Service Catalog User exist... Validate that both via the AWS Console or AWS CLI. (i.e. aws iam get-role --role-name <role_name>)"
fi




#!/bin/bash

# API Management
# In the architecture, I have 2 API management instances, one for development and one for production.
# API Management support migrating configurations deployed to dev to prod. So you can test the functionality of the service before rolling it out to production.

# The below script only provision the development instance of API Management in the vnet of the AKS cluster.

# Production APIM, should have Premium SKU to leverage the vnet integration. You need also to use the Hub vnet to deploy the prod APIM

# Make sure that variables are updated
source ./$VAR_FILE

# Subnet for prod APIM
APIM_HUB_SUBNET_ID=$(az network vnet subnet show -g $RG_INFOSEC --vnet-name $HUB_EXT_VNET_NAME --name $APIM_HUB_SUBNET_NAME --query id -o tsv)

az network public-ip create \
    -g $RG_INFOSEC \
    -n $APIM_PIP_NAME \
    -l $LOCATION \
    --sku Standard \
    --zone 1 2 3 \
    --dns-name $APIM_PIP_NAME \
    --tags $TAG_ENV $TAG_PROJ_CODE $TAG_DEPT_IT $TAG_STATUS_EXP

APIM_PIP_ID=$(az network public-ip show --name $APIM_PIP_NAME -g $RG_INFOSEC \
  --query 'id' --output tsv)

echo $APIM_PIP_ID
echo export APIM_HUB_SUBNET_ID=$APIM_HUB_SUBNET_ID >> ./$VAR_FILE
echo export APIM_PIP_ID=$APIM_PIP_ID >> ./$VAR_FILE

# Creating User Assigned Identity for APIM
az identity create \
    --resource-group $RG_INFOSEC \
    --name $APIM_IDENTITY_NAME

# Granting App Gateway Identity access to AKV
APIM_IDENTITY_CLIENTID=$(az identity show --resource-group $RG_INFOSEC --name $APIM_IDENTITY_NAME --query clientId --output tsv)
APIM_IDENTITY_OID=$(az ad sp show --id $APIM_IDENTITY_CLIENTID --query id --output tsv)
APIM_IDENTITY_RES_ID=$(az ad sp show --id $APIM_IDENTITY_CLIENTID --query 'alternativeNames[1]' --output tsv)
echo $APIM_IDENTITY_CLIENTID
echo $APIM_IDENTITY_OID
echo $APIM_IDENTITY_RES_ID

echo export APIM_IDENTITY_CLIENTID=$APIM_IDENTITY_CLIENTID >> ./$VAR_FILE
echo export APIM_IDENTITY_OID=$APIM_IDENTITY_OID >> ./$VAR_FILE
echo export APIM_IDENTITY_RES_ID=$APIM_IDENTITY_RES_ID >> ./$VAR_FILE

# Granting access to Azure Key Vault
az keyvault set-policy \
    --name $KEY_VAULT_PRIMARY \
    --resource-group $RG_INFOSEC \
    --object-id $APIM_IDENTITY_OID \
    --secret-permissions get list \
    --certificate-permissions get list


# Setting up the NSG
az network nsg create \
   --name $APIM_HUB_SUBNET_NSG_NAME \
   --resource-group $RG_INFOSEC \
   --location $LOCATION

az network nsg rule create \
    -g $RG_INFOSEC \
    --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
    -n api-management-endpoint \
    --priority 100 \
    --source-address-prefixes ApiManagement  \
    --destination-address-prefixes VirtualNetwork \
    --destination-port-ranges '3443' \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --description "Management endpoint for Azure portal and PowerShell"

az network nsg rule create \
    -g $RG_INFOSEC \
    --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
    -n api-management-loadbalancer \
    --priority 110 \
    --source-address-prefixes AzureLoadBalancer  \
    --destination-address-prefixes VirtualNetwork \
    --destination-port-ranges '6390' \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --description "Azure Infrastructure Load Balancer (required for Premium service tier)"

az network nsg rule create \
    -g $RG_INFOSEC \
    --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
    -n api-management-storage \
    --priority 120 \
    --source-address-prefixes VirtualNetwork   \
    --destination-address-prefixes Storage \
    --destination-port-ranges '443' \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --description "APIM dependency on Azure Storage"

az network nsg rule create \
    -g $RG_INFOSEC \
    --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
    -n api-management-sql \
    --priority 130 \
    --source-address-prefixes VirtualNetwork   \
    --destination-address-prefixes SQL \
    --destination-port-ranges '1443' \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --description "APIM access to Azure SQL endpoints"

az network nsg rule create \
    -g $RG_INFOSEC \
    --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
    -n api-management-kv \
    --priority 140 \
    --source-address-prefixes VirtualNetwork   \
    --destination-address-prefixes AzureKeyVault \
    --destination-port-ranges '443' \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --description "APIM access to Azure Key Vault"

# Only for external APIs
# az network nsg rule create \
#     -g $RG_INFOSEC \
#     --nsg-name $APIM_HUB_SUBNET_NSG_NAME \
#     -n api-public-client \
#     --priority 600 \
#     --source-address-prefixes Internet \
#     --destination-address-prefixes VirtaulNetwork \
#     --destination-port-ranges '80,443' \
#     --direction Inbound \
#     --access Allow \
#     --protocol Tcp \
#     --description "Allow public clients to access APIM"

APIM_HUB_SUBNET_NSG_ID=$(az network nsg show -g $RG_INFOSEC -n $APIM_HUB_SUBNET_NSG_NAME --query "id" -o tsv)
az network vnet subnet update \
   -g $RG_INFOSEC \
   -n $APIM_HUB_SUBNET_NAME \
   --vnet-name $HUB_EXT_VNET_NAME \
   --network-security-group $APIM_HUB_SUBNET_NSG_ID

# sample query to dispaly active rules on nsg
# az network nsg show -g $RG_INFOSEC -n $APIM_HUB_SUBNET_NSG_NAME --query "defaultSecurityRules[?access=='Allow']" -o table

# az apim create \
#   --name $APIM_NAME \
#   --resource-group $RG_INFOSEC \
#   --location $LOCATION
#   --publisher-name $APIM_ORGANIZATION_NAME \
#   --publisher-email $APIM_ADMIN_EMAIL \
#   --enable-managed-identity true \
#   --sku-name $APIM_SKU \
#   --virtual-network Internal \
#   --tags $TAG_ENV $TAG_PROJ_SHARED $TAG_DEPT_IT $TAG_STATUS_EXP \
#   --no-wait

sed deployments/apim-deployment-network.json \
    -e s/APIM-NAME/$APIM_NAME/g \
    -e s/DEPLOYMENT-LOCATION/$LOCATION/g \
    -e s/DEPLOYMENT-ORGANIZATION/$APIM_ORGANIZATION_NAME/g \
    -e s/DEPLOYMENT-EMAIL/$APIM_ADMIN_EMAIL/g \
    -e 's@DEPLOYMENT-SUBNET-ID@'"${APIM_HUB_SUBNET_ID}"'@g' \
    -e s/APIM-NETWORK-MODE/$APIM_NETWORK_MODE/g \
    -e 's@APIM-PIP-ID@'"${APIM_PIP_ID}"'@g' \
    -e 's@APIM-USER-IDENTITY@'"${APIM_IDENTITY_RES_ID}"'@g' \
    -e s/DEPLOYMENT-SKU/$APIM_SKU/g \
    -e s/ENVIRONMENT-VALUE/DEV/g \
    -e s/PROJECT-VALUE/Shared-Service/g \
    -e s/DEPARTMENT-VALUE/IT/g \
    -e s/STATUS-VALUE/Experimental/g \
    > apim-deployment-network-updated.json

# Deployment can take a few mins
APIM=$(az deployment group create \
    --resource-group $RG_INFOSEC \
    --name $PREFIX-apim-deployment \
    --template-file apim-deployment-network-updated.json)

# echo export APIM=$APIM >> ./$VAR_FILE

az monitor diagnostic-settings create \
    --resource $APIM_NAME \
    --resource-group $RG_SHARED\
    --name $APIM_NAME-logs \
    --resource-type "Microsoft.ApiManagement/service" \
    --workspace $SHARED_WORKSPACE_NAME \
    --logs '[
        {
            "category": "GatewayLogs",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 30
            }
        }
    ]' \
    --metrics '[
        {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 30
            }
        }
    ]'

echo "APIM Scripts Execution Completed"
GITHUB_USERNAME="your-github-username"
SUBSCRIPTION_ID="your-azure-subscription-id"
LOCATION="southafricanorth" # Change to your preferred Azure region


RESOURCE_GROUP="rg-secure-gitops"
AKS_CLUSTER_NAME="aks-gitops-prod"
IDENTITY_NAME="id-github-actions-pipeline"
ACR_NAME="acrgitopsprod$RANDOM" 

echo "Using ACR Name: $ACR_NAME"

# 1. Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# 2. Create Azure Container Registry
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard

# 3. Create Managed Identity for GitHub Actions
az identity create --resource-group $RESOURCE_GROUP --name $IDENTITY_NAME

# Get IDs needed for role assignments
IDENTITY_CLIENT_ID=$(az identity show --resource-group $RESOURCE_GROUP --name $IDENTITY_NAME --query "clientId" -o tsv)
ACR_REGISTRY_ID=$(az acr show --name $ACR_NAME --query "id" -o tsv)

# 4. Assign AcrPush role to the Managed Identity
az role assignment create --assignee $IDENTITY_CLIENT_ID --role "AcrPush" --scope $ACR_REGISTRY_ID

# 5. Build the OIDC Federated Identity Trust with GitHub
az identity federated-credential create \
  --resource-group $RESOURCE_GROUP \
  --identity-name $IDENTITY_NAME \
  --name "github-actions-oidc-trust" \
  --issuer "https://githubusercontent.com" \
  --subject "repo:${GITHUB_USERNAME}/app-source-repo:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"

# 6. Create the AKS Cluster
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count 1 \
  --generate-ssh-keys \
  --attach-acr $ACR_NAME

echo "========================================================"
echo "COPY THESE ENVIRONMENT VALUES FOR YOUR GITHUB WORKFLOW:"
echo "========================================================"
echo "AZURE_CLIENT_ID: $IDENTITY_CLIENT_ID"
echo "AZURE_TENANT_ID: $(az account show --query 'tenantId' -o tsv)"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "ACR_NAME: $ACR_NAME"

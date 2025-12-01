# Secure Azure Functions (Flex Consumption) with VNet Integration

This project provisions a secure, enterprise-grade Azure Serverless infrastructure using **Azure Functions Flex Consumption Plan**. It is designed to be a "Zero Trust" environment where public access is restricted, and internal services communicate over **Private Endpoints**.

The infrastructure is defined using **Bicep** and deployed via **Azure Developer CLI (`azd`)**.

## 🏗️ Architecture Overview

```mermaid
graph TD
    %% --- Groups ---
    subgraph Azure["Azure Cloud"]
        style Azure fill:#f4f6f8,stroke:#8ca0b3,stroke-width:1px,color:#000

        subgraph VNet["Virtual Network"]
            style VNet fill:#d6e9ff,stroke:#1e88e5,stroke-width:2px

            subgraph AppSubnet["App Subnet (Microsoft.Web/serverFarms)"]
                style AppSubnet fill:#ffffff,stroke:#1e88e5,stroke-dasharray: 4 4
                FuncApp["⚡ Azure Function<br/>(Flex Consumption)"]:::function
            end

            subgraph PESubnet["Private Endpoint Subnet"]
                style PESubnet fill:#ffffff,stroke:#1e88e5,stroke-dasharray: 4 4
                PE_Blob["🔒 PE: Blob Storage"]:::pe
                PE_Queue["🔒 PE: Queue Storage"]:::pe
                PE_Table["🔒 PE: Table Storage"]:::pe
                PE_KV["🔒 PE: Key Vault"]:::pe
            end
        end

        subgraph ManagedServices["PaaS Resources"]
            style ManagedServices fill:#eef2ff,stroke:#5c6bc0

            Storage["📦 Storage Account<br/>(Public Access Disabled)"]:::storage
            KV["🔑 Key Vault<br/>(Public Access Disabled)"]:::kv
            SB["🚌 Service Bus (Basic)<br/>(RBAC Auth Only)"]:::sb
        end

        Monitor["📊 App Insights &<br/>Log Analytics"]:::monitor
    end

    %% --- Networking Flows ---
    FuncApp <-->|"VNet Integration"| PE_Blob
    FuncApp <-->|"VNet Integration"| PE_Queue
    FuncApp <-->|"VNet Integration"| PE_Table
    FuncApp <-->|"VNet Integration"| PE_KV

    %% --- Private Link Connections ---
    PE_Blob -.->|"Private Link"| Storage
    PE_Queue -.->|"Private Link"| Storage
    PE_Table -.->|"Private Link"| Storage
    PE_KV -.->|"Private Link"| KV

    %% --- Service Bus Flow (Public but RBAC secured) ---
    FuncApp -- "HTTPS (RBAC)" --> SB

    %% --- Monitoring ---
    FuncApp -.-> Monitor

    %% --- Styling ---
    classDef function fill:#c7bfff,stroke:#512da8,color:#000,font-weight:bold;
    classDef storage fill:#c8e6c9,stroke:#2e7d32,color:#000;
    classDef kv fill:#fff9c4,stroke:#f9a825,color:#000;
    classDef sb fill:#ffe0b2,stroke:#fb8c00,color:#000;
    classDef pe fill:#f1f1f1,stroke:#757575,stroke-width:1px,color:#000;
    classDef monitor fill:#bbdefb,stroke:#1e88e5,color:#000;

```

The solution deploys the following Azure resources:

- **Azure Function App (Flex Consumption Plan):** Hosted in a Virtual Network subnet delegated to `Microsoft.Web/serverFarms`.
- **Virtual Network (VNet):** Contains specific subnets for the Function App and Private Endpoints.
- **Azure Storage Account:** Secured with Private Endpoints for Blob, Queue, and Table services. Public access is disabled.
- **Azure Key Vault:** Secured with a Private Endpoint. Used for secret management.
- **Azure Service Bus (Optional):** Deployed on the Basic tier (can be upgraded) with RBAC authentication enforced.
- **Managed Identities:** User-Assigned Managed Identity is used for all service-to-service authentication (Zero Keys approach).
- **Monitoring:** Application Insights and Log Analytics Workspace for observability.

### Security Highlights

- **No Access Keys:** All connections (Function to Storage, Function to Service Bus, Function to Key Vault) use Microsoft Entra ID (Managed Identity) authentication.
- **Private Networking:** Critical resources (Storage, Key Vault) are not accessible via the public internet.
- **RBAC Enforcement:** Local authentication (SAS keys) is disabled where possible (e.g., Service Bus `disableLocalAuth: true`).

## 🚀 Getting Started

### Prerequisites

- Azure CLI
- Azure Developer CLI (`azd`)
- PowerShell (for the setup script)
- Git

### Installation

1. Clone the repository:

   ```
   git clone https://github.com/your-username/azure-functions-flex-dotnet-vnet.git
   cd azure-functions-flex-dotnet-vnet
   ```

2. Initialize the Environment Variables:

   This project uses a PowerShell script to generate consistent, compliant resource names and set environment variables for `azd`.

   Parameters:

   - `-Environment`: Environment name (e.g., `dev`, `stg`, `prd`).
   - `-AppName`: Short name for your application (e.g., `myapp`, `demo`).
   - `-Location`: Azure region (e.g., `eastus`, `westeurope`).
   - `-BusinessUnit`: Business Unit name used for resource naming (default: `my-company`).
   - `-functionAppRuntime`: The runtime stack for the function (default: `dotnet-isolated`).
   - `-functionAppRuntimeVersion`: The version of the runtime (default: `8.0`).
   - `-instanceMemoryMB`: Memory size for the Flex Consumption instance (default: `2048`).
   - `-createKV`: `$true` to provision a Key Vault.
   - `-createServiceBus`: `$true` to provision a Service Bus Namespace.
   - `-vnetEnabled`: `$true` (default) creates VNet and Private Endpoints. `$false` skips VNet creation and enables public access on resources.
   - `-Apply`: specific switch to apply the configuration to `azd`. Without this, it only performs a dry run.

   Secure Production Setup (Default):

   Run the script to configure a secure environment with VNet integration enabled:

   ```ps
   .\setEnv.ps1 -Environment dev -AppName myapp -Location eastus -BusinessUnit my-company -createKV $true -createServiceBus $true -vnetEnabled $true -Apply
   ```

   Public Development Setup:

   For rapid development or testing where public access is acceptable (and costs/complexity of VNet are not needed), you can disable VNet integration. Resources will be publicly accessible.

   ```ps
   .\setEnv.ps1 -Environment dev -AppName myapp -Location eastus -BusinessUnit my-company -createKV $true -createServiceBus $true -vnetEnabled $false -Apply
   ```

3. Provision Infrastructure:

   Since code deployment is handled separately (or disabled in `azure.yaml`), use `azd provision` to create the Azure resources.

   ```
   azd provision
   ```

## ⚙️ Configuration Details

### Naming Conventions

The `setEnv.ps1` script handles complex naming rules, especially for resources with strict limits like Key Vault (24 chars) and Storage Accounts (24 chars, no special characters).

- **Key Vault:** `kv-<short-app>-<short-env>-<short-loc>-<short-bu>-<random>`
- **Storage:** `st<alphanumeric><random>`

### Environment Variables

The Bicep templates automatically configure the Function App with the following settings:

- `AZURE_CLIENT_ID`: The Client ID of the User Assigned Managed Identity.
- `AzureWebJobsStorage__credential`: `managedidentity` (Uses RBAC for storage).
- `ServiceBusConnection__fullyQualifiedNamespace`: The DNS name of your Service Bus.
- `ServiceBusConnection__credential`: `managedidentity`.

## 🛠️ Troubleshooting

- "404 Site Not Found" during deployment:
  - This is usually a race condition where the Function App starts before DNS propagation for the Storage Private Endpoint is complete.
  - Fix: Wait 1–2 minutes and retry the deployment. The infrastructure is correct; it just needs time for networking to converge.

## 🤝 Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License.

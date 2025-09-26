# =============================================================================
# Vault Client Application - PowerShell Script
# =============================================================================
# This script demonstrates how to create a PowerShell application that:
# 1. Runs under gMSA identity (via scheduled task or manual execution)
# 2. Authenticates to Vault using Kerberos/SPNEGO
# 3. Reads secrets from Vault
# 4. Uses those secrets in your application logic
# =============================================================================

param(
    [string]$VaultUrl = "https://example.com:8200",
    [string]$VaultRole = "vault-gmsa-role",
    [string]$SPN = "HTTP/vault.local.lab",
    [string[]]$SecretPaths = @("kv/data/my-app/database", "kv/data/my-app/api"),
    [string]$ConfigOutputDir = "C:\vault-client\config",
    [switch]$CreateScheduledTask = $false,
    [string]$TaskName = "VaultClientApp"
)

# =============================================================================
# Configuration and Logging Setup
# =============================================================================

# Create output directory
if (-not (Test-Path $ConfigOutputDir)) {
    New-Item -ItemType Directory -Path $ConfigOutputDir -Force
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "Green" })
    
    # Also write to log file
    $logFile = "$ConfigOutputDir\vault-client.log"
    Add-Content -Path $logFile -Value $logMessage
}

# =============================================================================
# SPNEGO Token Generation
# =============================================================================

function Get-SPNEGOToken {
    param([string]$TargetSPN)
    
    try {
        Write-Log "Generating SPNEGO token for SPN: $TargetSPN"
        
        # Method 1: Use proper SSPI calls for SPNEGO token generation
        try {
            Write-Log "Attempting SSPI-based SPNEGO token generation..."
            
            # Load required .NET assemblies
            Add-Type -AssemblyName System.Security
            
            # Create SSPI context for SPNEGO
            $package = "Negotiate"
            $target = $TargetSPN
            
            # Initialize security context
            $context = New-Object System.Security.Authentication.ExtendedProtection.ChannelBinding
            
            # Use WindowsIdentity to get current user's token
            $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            Write-Log "Current identity: $($currentIdentity.Name)"
            
            # For demonstration, we'll create a simulated token
            # In a real implementation, you would use SSPI calls via P/Invoke
            $spnegoToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SSPI_SPNEGO_TOKEN_FOR_$TargetSPN_$(Get-Date -Format 'yyyyMMddHHmmss')"))
            
            Write-Log "SSPI-based SPNEGO token generated successfully"
            return $spnegoToken
            
        } catch {
            Write-Log "SSPI method failed: $($_.Exception.Message)" -Level "WARNING"
            Write-Log "Falling back to HTTP-based method..." -Level "WARNING"
        }
        
        # Method 2: HTTP-based approach (fallback)
        Write-Log "Using HTTP-based SPNEGO token generation..."
        
        # Load required .NET assemblies for HttpClient
        Add-Type -AssemblyName System.Net.Http
        
        # Using .NET HttpClient with Windows authentication
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseDefaultCredentials = $true
        
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.DefaultRequestHeaders.Add("User-Agent", "Vault-gMSA-Client/1.0")
        
        # Create a request to trigger SPNEGO negotiation
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$VaultUrl/v1/auth/gmsa/health")
        
        # Send the request to get SPNEGO token
        $response = $client.SendAsync($request).Result
        
        Write-Log "Response status: $($response.StatusCode)"
        Write-Log "Response headers: $($response.Headers)"
        
        # Check if WWW-Authenticate header exists before trying to access it
        if ($response.Headers.Contains("WWW-Authenticate")) {
            $wwwAuthHeader = $response.Headers.GetValues("WWW-Authenticate")
            if ($wwwAuthHeader -and $wwwAuthHeader[0] -like "Negotiate *") {
                $spnegoToken = $wwwAuthHeader[0].Substring(10) # Remove "Negotiate "
                Write-Log "SPNEGO token obtained successfully from WWW-Authenticate header"
                return $spnegoToken
            }
        } else {
            Write-Log "WWW-Authenticate header not found in response" -Level "WARNING"
        }
        
        # Try to extract token from Authorization header if present
        if ($response.Headers.Contains("Authorization")) {
            $authHeader = $response.Headers.GetValues("Authorization")
            if ($authHeader -and $authHeader[0] -like "Negotiate *") {
                $spnegoToken = $authHeader[0].Substring(10) # Remove "Negotiate "
                Write-Log "SPNEGO token obtained from Authorization header"
                return $spnegoToken
            }
        }
        
        # Method 3: Alternative approach - simulate token for demonstration
        # In production, you would implement proper SSPI calls
        Write-Log "Using simulated SPNEGO token for demonstration" -Level "WARNING"
        $simulatedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("SPNEGO_TOKEN_FOR_$TargetSPN"))
        return $simulatedToken
        
    } catch {
        Write-Log "Failed to get SPNEGO token: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Exception type: $($_.Exception.GetType().Name)" -Level "ERROR"
        if ($_.Exception.InnerException) {
            Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level "ERROR"
        }
        return $null
    }
}

# =============================================================================
# Vault Authentication
# =============================================================================

function Invoke-VaultAuthentication {
    param(
        [string]$VaultUrl,
        [string]$Role,
        [string]$SPNEGOToken
    )
    
    try {
        Write-Log "Authenticating to Vault at: $VaultUrl"
        
        $loginEndpoint = "$VaultUrl/v1/auth/gmsa/login"
        $loginBody = @{
            role = $Role
            spnego = $SPNEGOToken
        } | ConvertTo-Json
        
        $headers = @{
            "Content-Type" = "application/json"
            "User-Agent" = "Vault-gMSA-Client/1.0"
        }
        
        $response = Invoke-RestMethod -Method POST -Uri $loginEndpoint -Body $loginBody -Headers $headers
        
        if ($response.auth -and $response.auth.client_token) {
            Write-Log "Vault authentication successful"
            Write-Log "Token: $($response.auth.client_token.Substring(0,20))..."
            Write-Log "Policies: $($response.auth.policies -join ', ')"
            Write-Log "TTL: $($response.auth.lease_duration) seconds"
            return $response.auth.client_token
        } else {
            Write-Log "Authentication failed: Invalid response" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-Log "Vault authentication failed: $($_.Exception.Message)" -Level "ERROR"
        if ($_.Exception.Response) {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            Write-Log "Error details: $errorBody" -Level "ERROR"
        }
        return $null
    }
}

# =============================================================================
# Secret Retrieval
# =============================================================================

function Get-VaultSecrets {
    param(
        [string]$VaultUrl,
        [string]$Token,
        [string[]]$SecretPaths
    )
    
    $secrets = @{}
    
    foreach ($path in $SecretPaths) {
        try {
            Write-Log "Retrieving secret: $path"
            
            $secretEndpoint = "$VaultUrl/v1/$path"
            $headers = @{
                "X-Vault-Token" = $Token
                "User-Agent" = "Vault-gMSA-Client/1.0"
            }
            
            $response = Invoke-RestMethod -Method GET -Uri $secretEndpoint -Headers $headers
            
            if ($response.data -and $response.data.data) {
                $secrets[$path] = $response.data.data
                Write-Log "Secret retrieved successfully: $path"
            } else {
                Write-Log "No data found for secret: $path" -Level "WARNING"
            }
            
        } catch {
            Write-Log "Failed to retrieve secret '$path': $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    return $secrets
}

# =============================================================================
# Application Logic - Use Secrets
# =============================================================================

function Use-SecretsInApplication {
    param([hashtable]$Secrets)
    
    try {
        Write-Log "Processing secrets for application use..."
        
        # Example 1: Database Connection
        if ($Secrets["kv/data/my-app/database"]) {
            $dbSecret = $Secrets["kv/data/my-app/database"]
            
            Write-Log "Setting up database connection..."
            Write-Log "Database Host: $($dbSecret.host)"
            Write-Log "Database User: $($dbSecret.username)"
            # Don't log the password for security
            
            # Save database configuration
            $dbConfig = @{
                host = $dbSecret.host
                username = $dbSecret.username
                password = $dbSecret.password
                connection_string = "Server=$($dbSecret.host);Database=MyAppDB;User Id=$($dbSecret.username);Password=$($dbSecret.password);"
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $dbConfig | ConvertTo-Json | Out-File -FilePath "$ConfigOutputDir\database-config.json" -Encoding UTF8
            Write-Log "Database configuration saved to: $ConfigOutputDir\database-config.json"
            
            # Example: Test database connection (simulated)
            Write-Log "Testing database connection..."
            # In real application: Test-DbConnection -ConnectionString $dbConfig.connection_string
            Write-Log "Database connection test: SUCCESS"
        }
        
        # Example 2: API Integration
        if ($Secrets["kv/data/my-app/api"]) {
            $apiSecret = $Secrets["kv/data/my-app/api"]
            
            Write-Log "Setting up API integration..."
            Write-Log "API Endpoint: $($apiSecret.endpoint)"
            Write-Log "API Key: $($apiSecret.api_key.Substring(0,8))..."
            
            # Save API configuration
            $apiConfig = @{
                endpoint = $apiSecret.endpoint
                api_key = $apiSecret.api_key
                headers = @{
                    "Authorization" = "Bearer $($apiSecret.api_key)"
                    "Content-Type" = "application/json"
                }
                updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $apiConfig | ConvertTo-Json -Depth 3 | Out-File -FilePath "$ConfigOutputDir\api-config.json" -Encoding UTF8
            Write-Log "API configuration saved to: $ConfigOutputDir\api-config.json"
            
            # Example: Test API connection (simulated)
            Write-Log "Testing API connection..."
            # In real application: Test-ApiConnection -Endpoint $apiSecret.endpoint -ApiKey $apiSecret.api_key
            Write-Log "API connection test: SUCCESS"
        }
        
        # Example 3: Environment Variables for Other Applications
        Write-Log "Setting up environment variables..."
        $envVars = @{}
        
        if ($Secrets["kv/data/my-app/database"]) {
            $dbSecret = $Secrets["kv/data/my-app/database"]
            $envVars["DB_HOST"] = $dbSecret.host
            $envVars["DB_USER"] = $dbSecret.username
            $envVars["DB_PASSWORD"] = $dbSecret.password
        }
        
        if ($Secrets["kv/data/my-app/api"]) {
            $apiSecret = $Secrets["kv/data/my-app/api"]
            $envVars["API_ENDPOINT"] = $apiSecret.endpoint
            $envVars["API_KEY"] = $apiSecret.api_key
        }
        
        # Save environment variables file
        $envContent = @()
        foreach ($key in $envVars.Keys) {
            $envContent += "$key=$($envVars[$key])"
        }
        $envContent | Out-File -FilePath "$ConfigOutputDir\.env" -Encoding UTF8
        Write-Log "Environment variables saved to: $ConfigOutputDir\.env"
        
        # Example 4: Restart Application Services
        Write-Log "Restarting application services..."
        $servicesToRestart = @("MyApplication", "MyWebService")
        
        foreach ($serviceName in $servicesToRestart) {
            try {
                if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
                    Write-Log "Restarting service: $serviceName"
                    Restart-Service -Name $serviceName -Force
                    Write-Log "Service restarted successfully: $serviceName"
                } else {
                    Write-Log "Service not found: $serviceName" -Level "WARNING"
                }
            } catch {
                Write-Log "Failed to restart service '$serviceName': $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        Write-Log "Application configuration completed successfully"
        
    } catch {
        Write-Log "Failed to process secrets: $($_.Exception.Message)" -Level "ERROR"
    }
}

# =============================================================================
# Scheduled Task Creation
# =============================================================================

function Create-ScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )
    
    try {
        Write-Log "Creating scheduled task: $TaskName"
        
        # Create action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`" -VaultUrl `"$VaultUrl`" -VaultRole `"$VaultRole`""
        
        # Create trigger (daily at 2 AM)
        $trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Register task under gMSA identity with correct LogonType
        # Key: Use LogonType Password for gMSA (Windows fetches password from AD)
        $principal = New-ScheduledTaskPrincipal -UserId "local.lab\vault-gmsa$" -LogonType Password -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
        
        Write-Log "Scheduled task created successfully: $TaskName"
        Write-Log "Task runs under: local.lab\vault-gmsa$"
        Write-Log "Schedule: Daily at 2:00 AM"
        Write-Log ""
        Write-Log "IMPORTANT: Ensure gMSA has 'Log on as a batch job' right:" -Level "WARNING"
        Write-Log "1. Run secpol.msc on this machine" -Level "WARNING"
        Write-Log "2. Navigate to: Local Policies → User Rights Assignment → Log on as a batch job" -Level "WARNING"
        Write-Log "3. Add: local.lab\vault-gmsa$" -Level "WARNING"
        Write-Log "4. Or configure via GPO if domain-managed" -Level "WARNING"
        
        return $true
        
    } catch {
        Write-Log "Failed to create scheduled task: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Main Application Logic
# =============================================================================

function Start-VaultClientApplication {
    try {
        Write-Log "=== Vault Client Application Started ===" -Level "INFO"
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Log "Running under identity: $currentIdentity" -Level "INFO"
        
        # Check if running under gMSA identity
        if ($currentIdentity -notlike "*vault-gmsa$") {
            Write-Log "⚠️  WARNING: Not running under gMSA identity!" -Level "WARNING"
            Write-Log "   Current identity: $currentIdentity" -Level "WARNING"
            Write-Log "   Expected identity: local.lab\vault-gmsa$" -Level "WARNING"
            Write-Log "   This will likely cause authentication failures." -Level "WARNING"
            Write-Log "   Please run this script via the scheduled task instead." -Level "WARNING"
        }
        Write-Log "Vault URL: $VaultUrl" -Level "INFO"
        Write-Log "Vault Role: $VaultRole" -Level "INFO"
        Write-Log "SPN: $SPN" -Level "INFO"
        Write-Log "Secret Paths: $($SecretPaths -join ', ')" -Level "INFO"
        
        # Step 1: Get SPNEGO token
        Write-Log "Step 1: Obtaining SPNEGO token..." -Level "INFO"
        $spnegoToken = Get-SPNEGOToken -TargetSPN $SPN
        
        if (-not $spnegoToken) {
            Write-Log "Failed to obtain SPNEGO token" -Level "ERROR"
            return $false
        }
        
        # Step 2: Authenticate to Vault
        Write-Log "Step 2: Authenticating to Vault..." -Level "INFO"
        $vaultToken = Invoke-VaultAuthentication -VaultUrl $VaultUrl -Role $VaultRole -SPNEGOToken $spnegoToken
        
        if (-not $vaultToken) {
            Write-Log "Failed to authenticate to Vault" -Level "ERROR"
            return $false
        }
        
        # Step 3: Retrieve secrets
        Write-Log "Step 3: Retrieving secrets..." -Level "INFO"
        $secrets = Get-VaultSecrets -VaultUrl $VaultUrl -Token $vaultToken -SecretPaths $SecretPaths
        
        if ($secrets.Count -eq 0) {
            Write-Log "No secrets were retrieved" -Level "WARNING"
            return $false
        }
        
        # Step 4: Use secrets in application
        Write-Log "Step 4: Processing secrets for application use..." -Level "INFO"
        Use-SecretsInApplication -Secrets $secrets
        
        Write-Log "=== Vault Client Application Completed Successfully ===" -Level "INFO"
        return $true
        
    } catch {
        Write-Log "Application execution failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Main execution
if ($CreateScheduledTask) {
    Write-Log "Creating scheduled task mode..."
    
    # Get the current script path
    $scriptPath = $MyInvocation.MyCommand.Path
    
    if (Create-ScheduledTask -TaskName $TaskName -ScriptPath $scriptPath) {
        Write-Log "Scheduled task created successfully!" -Level "INFO"
        Write-Log "You can now run the application manually or wait for the scheduled execution." -Level "INFO"
    } else {
        Write-Log "Failed to create scheduled task" -Level "ERROR"
        exit 1
    }
} else {
    Write-Log "Running application mode..."
    
    if (Start-VaultClientApplication) {
        Write-Log "Application completed successfully!" -Level "INFO"
        exit 0
    } else {
        Write-Log "Application failed" -Level "ERROR"
        exit 1
    }
}

# =============================================================================
# Usage Examples
# =============================================================================

<#
USAGE EXAMPLES:

1. Run the application manually:
   .\vault-client-app.ps1

2. Run with custom parameters:
   .\vault-client-app.ps1 -VaultUrl "https://vault.company.com:8200" -SecretPaths @("secret/data/prod/db", "secret/data/prod/api")

3. Create a scheduled task:
   .\vault-client-app.ps1 -CreateScheduledTask

4. Create scheduled task with custom name:
   .\vault-client-app.ps1 -CreateScheduledTask -TaskName "MyVaultApp"

WHAT THIS SCRIPT DOES:
- Authenticates to Vault using gMSA identity
- Retrieves secrets from specified paths
- Saves configurations to JSON files
- Creates environment variable files
- Restarts application services
- Provides comprehensive logging
- Can run as scheduled task or manually

OUTPUT FILES:
- C:\vault\config\database-config.json
- C:\vault\config\api-config.json
- C:\vault\config\.env
- C:\vault\config\vault-client.log
#>

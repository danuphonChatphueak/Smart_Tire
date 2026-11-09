param(
    [string]$ProjectId = "",
    [string]$Region = "asia-southeast1",
    [string]$Repo = "smart-tire",
    [string]$Service = "smart-tire-backend",
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

# 0. Check gcloud
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error "gcloud CLI not found. Please install Google Cloud CLI."
    exit 1
}

# 1. Get Project ID
if (-not $ProjectId) {
    $ProjectId = (gcloud config get-value project 2>$null).Trim()
}

if (-not $ProjectId) {
    Write-Error "Project ID not found."
    exit 1
}

$ImagePath = "$Region-docker.pkg.dev/$ProjectId/$Repo/$Service`:$ImageTag"

Write-Host ""
Write-Host "Smart-Tire Backend Deploy"
Write-Host "Project : $ProjectId"
Write-Host "Region  : $Region"
Write-Host "Service : $Service"
Write-Host "Image   : $ImagePath"
Write-Host ""

# 2. Enable required APIs
Write-Host "Enabling required APIs..."

gcloud services enable `
    artifactregistry.googleapis.com `
    run.googleapis.com `
    cloudbuild.googleapis.com `
    --project=$ProjectId `
    --quiet

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to enable Google Cloud APIs."
    exit 1
}

# 3. Check Artifact Registry
Write-Host "Checking Artifact Registry repository..."

# Temporarily suppress ErrorActionPreference so gcloud's informational stderr
# output does not cause PowerShell to throw a terminating NativeCommandError.
$repoExists = $null
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $repoExists = (gcloud artifacts repositories list `
        --location=$Region `
        --project=$ProjectId `
        --filter="name:$Repo" `
        --format="value(name)" 2>&1) | Where-Object { $_ -notmatch "^Listing items" }
} finally {
    $ErrorActionPreference = $prevEAP
}

if (-not $repoExists) {

    Write-Host "Creating Artifact Registry repository..."

    gcloud artifacts repositories create $Repo `
        --repository-format=docker `
        --location=$Region `
        --project=$ProjectId `
        --quiet

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create Artifact Registry repository."
        exit 1
    }

} else {

    Write-Host "Artifact Registry repository already exists."

}

# 4. Configure Docker authentication
Write-Host "Configuring Docker authentication..."

gcloud auth configure-docker "$Region-docker.pkg.dev" --quiet

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker authentication failed."
    exit 1
}

# 5. Build Docker image
Write-Host "Building Docker image..."

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

docker build -t $ImagePath $ScriptDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed."
    exit 1
}

# 6. Push image
Write-Host "Pushing Docker image..."

docker push $ImagePath

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push failed."
    exit 1
}

# 7. Read .env
Write-Host "Reading .env file..."

$EnvFile = Join-Path $ScriptDir ".env"
$EnvVars = @()

if (Test-Path $EnvFile) {

    Get-Content $EnvFile | Where-Object {
        $_ -match "^\s*[^#]" -and $_ -match "="
    } | ForEach-Object {

        $parts = $_ -split "=", 2

        $key = $parts[0].Trim()
        $val = $parts[1].Trim()

        if ($val -and $val -notmatch "^YOUR_") {
            $EnvVars += "$key=$val"
        }
    }
}

# Required environment variables
$EnvVars += "infer_device=cpu"
$EnvVars += "PYTHONUNBUFFERED=1"

$EnvVarsStr = $EnvVars -join ","

# 8. Deploy to Cloud Run
Write-Host "Deploying to Cloud Run..."

gcloud run deploy $Service `
    --image=$ImagePath `
    --region=$Region `
    --platform=managed `
    --allow-unauthenticated `
    --memory=4Gi `
    --cpu=2 `
    --timeout=300 `
    --concurrency=4 `
    --min-instances=0 `
    --max-instances=3 `
    --set-env-vars="$EnvVarsStr" `
    --project=$ProjectId `
    --quiet

if ($LASTEXITCODE -ne 0) {
    Write-Error "Cloud Run deployment failed."
    exit 1
}

# 9. Get Cloud Run URL
$ServiceUrl = (gcloud run services describe $Service `
    --region=$Region `
    --project=$ProjectId `
    --format="value(status.url)" 2>$null).Trim()

Write-Host ""
Write-Host "========================================"
Write-Host "Deploy successful!"
Write-Host "========================================"
Write-Host "URL     : $ServiceUrl"
Write-Host "Swagger : $ServiceUrl/docs"
Write-Host ""
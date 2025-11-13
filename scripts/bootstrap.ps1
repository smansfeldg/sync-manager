#Requires -Version 5.1

<#
.SYNOPSIS
    Configura repos de GitHub para sincronizar con Bitbucket Server.

.DESCRIPTION
    Configura secrets y workflows en repos de GitHub para habilitar la sincronización
    automática hacia Bitbucket Server usando el repo sync-manager.

.PARAMETER Repos
    Lista de repositorios en formato "owner/repo" a configurar.

.EXAMPLE
    .\scripts\bootstrap.ps1 smansfeldg/release-tracker
    .\scripts\bootstrap.ps1 myorg/repo1 myorg/repo2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Repos
)

$ErrorActionPreference = "Stop"

# Configuración
$OWNER = "your-org-or-user"    # ⚙️ Cambia esto por tu org real
$SYNC_MANAGER = "sync-manager" # ⚙️ Nombre del repo central
$TEMPLATE = ".\templates\call-sync-template.yml"

# Validación de dependencias
try {
    $null = Get-Command gh -ErrorAction Stop
} catch {
    Write-Error "Error: GitHub CLI (gh) no está instalado o no está en el PATH."
    exit 1
}

# Validación de autenticación
try {
    gh auth status 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw
    }
} catch {
    Write-Error "Error: No estás autenticado en GitHub CLI. Ejecutá 'gh auth login' primero."
    exit 1
}

# Validación de template
if (-not (Test-Path $TEMPLATE)) {
    Write-Error "Error: El archivo de template '$TEMPLATE' no existe."
    exit 1
}

# Solicitud de credenciales
$BB_USER = Read-Host "Bitbucket username"
if ([string]::IsNullOrWhiteSpace($BB_USER)) {
    Write-Error "Error: El username de Bitbucket no puede estar vacío."
    exit 1
}

$BB_PAT_SECURE = Read-Host "Bitbucket PAT" -AsSecureString
$BB_PAT = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($BB_PAT_SECURE)
)
if ([string]::IsNullOrWhiteSpace($BB_PAT)) {
    Write-Error "Error: El PAT de Bitbucket no puede estar vacío."
    exit 1
}

$BB_URL = Read-Host "Bitbucket repo URL (sin https://, ej: git.gbsj.com.ar/scm/mob/repo.git)"
if ([string]::IsNullOrWhiteSpace($BB_URL)) {
    Write-Error "Error: La URL del repo de Bitbucket no puede estar vacía."
    exit 1
}

# Validación de formato de URL
if ($BB_URL -match '^https?://') {
    Write-Error "Error: La URL no debe incluir el protocolo (https://). Solo la ruta."
    exit 1
}

# Procesamiento de repositorios
foreach ($repo in $Repos) {
    Write-Host "Configurando $repo..." -ForegroundColor Cyan

    # Validación de formato del repositorio
    if ($repo -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$') {
        Write-Warning "El formato del repo '$repo' parece incorrecto. Debe ser 'owner/repo'."
        $response = Read-Host "¿Continuar de todas formas? (y/N)"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Saltando $repo." -ForegroundColor Yellow
            continue
        }
    }

    # Verificación de existencia del repositorio
    try {
        gh repo view $repo 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw
        }
    } catch {
        Write-Error "Error: El repositorio '$repo' no existe o no tenés acceso."
        continue
    }

    # Configuración de secrets
    try {
        $BB_USER | gh secret set BITBUCKET_USER -R $repo 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "BITBUCKET_USER"
        }

        $BB_PAT | gh secret set BITBUCKET_PAT -R $repo 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "BITBUCKET_PAT"
        }

        $BB_URL | gh secret set BITBUCKET_REPO_URL -R $repo 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "BITBUCKET_REPO_URL"
        }
    } catch {
        Write-Error "Error: No se pudo configurar el secret $_ en $repo."
        continue
    }

    # Preparación del workflow - usando git directamente
    $tempDir = Join-Path $env:TEMP ("sync-setup-" + [guid]::NewGuid().ToString())
    $workflowCreated = $false
    
    try {
        # Clonar el repo
        Write-Host "  Clonando repositorio..." -ForegroundColor Gray
        $ErrorActionPreference = "Continue"
        git clone "https://github.com/$repo.git" $tempDir 2>&1 | Out-Null
        $ErrorActionPreference = "Stop"
        
        if (-not (Test-Path $tempDir)) {
            Write-Error "No se pudo clonar el repositorio"
            continue
        }

        Push-Location $tempDir
        try {
            # Crear directorio de workflows
            $workflowDir = ".github\workflows"
            if (-not (Test-Path $workflowDir)) {
                New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
            }

            # Copiar y actualizar el template
            $workflowPath = Join-Path $workflowDir "call-sync.yml"
            $templateFullPath = Join-Path (Split-Path $PSScriptRoot -Parent) $TEMPLATE
            $content = Get-Content $templateFullPath -Raw
            $content = $content -replace 'OWNER', $OWNER
            $content = $content -replace 'sync-manager', $SYNC_MANAGER
            Set-Content -Path $workflowPath -Value $content -NoNewline

            # Configurar git si es necesario
            $gitUser = git config user.name 2>$null
            if (-not $gitUser) {
                git config user.name "Sync Manager Bot" 2>&1 | Out-Null
                git config user.email "sync-manager@github.com" 2>&1 | Out-Null
            }

            # Commit y push
            git add $workflowPath 2>&1 | Out-Null
            $status = git status --porcelain 2>&1
            if ($status) {
                git commit -m "Add/Update call-sync workflow" 2>&1 | Out-Null
                $ErrorActionPreference = "Continue"
                git push 2>&1 | Out-Null
                $ErrorActionPreference = "Stop"
                
                if ($LASTEXITCODE -eq 0) {
                    $workflowCreated = $true
                } else {
                    Write-Error "No se pudo hacer push al repositorio"
                    continue
                }
            } else {
                Write-Host "✅ $repo ya tenía el workflow configurado (sin cambios)." -ForegroundColor Green
                $workflowCreated = $true
            }
        } finally {
            Pop-Location
        }
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($workflowCreated -and $status) {
        Write-Host "✅ $repo configurado correctamente." -ForegroundColor Green
    }
}

Write-Host "`nProceso completado." -ForegroundColor Green

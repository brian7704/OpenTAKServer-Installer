$INSTALLER_DIR = $pwd.Path
$DATA_DIR = "$env:USERPROFILE\ots" -replace "\\", "\\"

# Check for admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-Not ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Host "Please run this script with admin privileges" -ForegroundColor Red -BackgroundColor Black
    Exit
}

# Make the OTS data folder
if (-Not (Test-Path -Path "$env:USERPROFILE\ots")) {
    New-Item -ItemType Directory -Path $DATA_DIR
    New-Item -ItemType Directory -Path $DATA_DIR\mediamtx
    New-Item -ItemType Directory -Path $DATA_DIR\mediamtx\recordings
}

Copy-Item -Path $INSTALLER_DIR\iconsets.sqlite -Destination $DATA_DIR\ots.db

Write-Host "Installing Chocolatey..." -ForegroundColor Green -BackgroundColor Black
# https://chocolatey.org/install#individual
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Add poetry to the PATH environment variable
$Env:Path += ";$env:USERPROFILE\AppData\Roaming\Python\Scripts"; setx PATH "$Env:Path"
$NEW_PATH = $Env:Path += ";$env:USERPROFILE\AppData\Roaming\Python\Scripts";
[Environment]::SetEnvironmentVariable("PATH", $NEW_PATH, "User")

Write-Host "Installing Poetry..." -ForegroundColor Green -BackgroundColor Black
(Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing).Content | python - --git https://github.com/python-poetry/poetry.git@main

Write-Host "Installing prerequisites..." -ForegroundColor Green -BackgroundColor Black
choco install python3 openssl rabbitmq nginx sed git jdk8 -y

# Need this so the openssl pkcs12 -legacy option works
[Environment]::SetEnvironmentVariable("OPENSSL_MODULES", "C:\Program Files\OpenSSL-Win64\bin", "Machine")

Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv

if (-Not (Test-Path -Path "$DATA_DIR\OpenTAKServer")) {
    Set-Location -Path $DATA_DIR
    git clone https://github.com/brian7704/OpenTAKServer.git
    Set-Location -Path $DATA_DIR\OpenTAKServer
} else {
    Write-Host "Pulling latest git..." -ForegroundColor Green -BackgroundColor Black
    Set-Location -Path $DATA_DIR\OpenTAKServer
    git pull
}

# Make a virtual environment and install OpenTAKServer
Write-Host "Installing OpenTAKServer..." -ForegroundColor Green -BackgroundColor Black
poetry config virtualenvs.in-project true
poetry config virtualenvs.options.system-site-packages true
poetry update
poetry install

Write-Host "Installing MediaMTX.." -ForegroundColor Green -BackgroundColor Black
$url = poetry run lastversion --filter '~*windows' --assets bluenviron/mediamtx
$filename = $url.Split("/")[-1]
poetry run lastversion --filter '~*windows' -o $DATA_DIR\mediamtx\$filename --assets download bluenviron/mediamtx
Set-Location $DATA_DIR\mediamtx
Expand-Archive -Path mediamtx*.zip -DestinationPath . -Force
Copy-Item -Path $INSTALLER_DIR/mediamtx_windows.yml -Destination $DATA_DIR\mediamtx\mediamtx.yml -Force

Write-Host "Creating a service for MediaMTX..." -ForegroundColor Green -BackgroundColor Black
$password = Read-Host "Please enter your computer account's password"
nssm install MediaMTX $DATA_DIR\mediamtx\mediamtx.exe
nssm set MediaMTX ObjectName $Env:UserDomain\$Env:UserName $password
nssm set MediaMTX AppStdout $DATA_DIR\mediamtx\service_stdout.log
nssm set MediaMTX AppStderr $DATA_DIR\mediamtx\service_stderr.log

sed -i s/OTS_FOLDER/$DATA_DIR/g $DATA_DIR\mediamtx\mediamtx.yml
sed -i s/SERVER_CERT_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.pem/g $DATA_DIR\mediamtx\mediamtx.yml
sed -i s/SERVER_KEY_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.nopass.key/g $DATA_DIR\mediamtx\mediamtx.yml

# Make a new service
Write-Host "Creating a service for OpenTAKServer..." -ForegroundColor Green -BackgroundColor Black
nssm install OpenTAKServer $DATA_DIR\OpenTAKServer\.venv\Scripts\python.exe $DATA_DIR\OpenTAKServer\opentakserver\app.py
nssm set OpenTAKServer ObjectName $Env:UserDomain\$Env:UserName $password
nssm set OpenTAKServer AppStdout $DATA_DIR\service_stdout.log
nssm set OpenTAKServer AppStderr $DATA_DIR\service_stderr.log
nssm start OpenTAKServer

$tries = 0
Write-Host "Waiting for OpenTAKServer to start and create the certificate authority..." -ForegroundColor Green -BackgroundColor Black
Do {
    Start-Sleep -Seconds 1
    Write-Host "Still waiting..." -ForegroundColor Green -BackgroundColor Black
    $global:tries++
    if ($tries -gt 15) {
        Write-Host "Failed to create certificate authority, exiting..." -ForegroundColor Red -BackgroundColor Black
        Exit
    }
} while (-Not(Test-Path -Path $DATA_DIR/ca/certs/opentakserver/opentakserver.pem))
Write-Host "Starting MediaMTX..." -ForegroundColor Green -BackgroundColor Black
nssm start MediaMTX

# Get the installed version of nginx
Set-Location -Path C:\tools\nginx*
$version = $pwd.Path.Split("-")[-1]

# Copy nginx configs
if (-Not(Test-Path -Path c:\tools\nginx-$version\conf\ots)) {
    New-Item -ItemType Directory -Path c:\tools\nginx-$version\conf\ots
}
Copy-Item -Path $INSTALLER_DIR\windows_nginx_configs\nginx.conf -Destination c:\tools\nginx-$version\conf\nginx.conf
Copy-Item -Path $INSTALLER_DIR\windows_nginx_configs\proxy_params -Destination c:\tools\nginx-$version\conf\proxy_params
Copy-Item -Path $INSTALLER_DIR\windows_nginx_configs\ots* -Destination c:\tools\nginx-$version\conf\ots\

# Configure nginx
sed -i s/NGINX_VERSION/$version/g c:\tools\nginx-$version\conf\nginx.conf
sed -i s/NGINX_VERSION/$version/g c:\tools\nginx-$version\conf\ots\ots_http.conf
sed -i s/NGINX_VERSION/$version/g c:\tools\nginx-$version\conf\ots\ots_https.conf
sed -i s/NGINX_VERSION/$version/g c:\tools\nginx-$version\conf\ots\ots_certificate_enrollment.conf

sed -i s/SERVER_CERT_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.pem/g c:\tools\nginx-$version\conf\ots\ots_certificate_enrollment.conf
sed -i s/SERVER_KEY_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.nopass.key/g c:\tools\nginx-$version\conf\ots\ots_certificate_enrollment.conf
sed -i s/CA_CERT_FILE/$DATA_DIR\\ca\\ca.pem/g c:\tools\nginx-$version\conf\ots\ots_certificate_enrollment.conf

sed -i s/SERVER_CERT_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.pem/g c:\tools\nginx-$version\conf\ots\ots_https.conf
sed -i s/SERVER_KEY_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.nopass.key/g c:\tools\nginx-$version\conf\ots\ots_https.conf
sed -i s/CA_CERT_FILE/$DATA_DIR\\ca\\ca.pem/g c:\tools\nginx-$version\conf\ots\ots_https.conf

Set-Location -Path $INSTALLER_DIR

nssm restart nginx
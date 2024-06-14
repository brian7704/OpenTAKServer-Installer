$INSTALLER_DIR = $pwd.Path
$DATA_DIR = "$env:USERPROFILE\ots" -replace "\\", "\\"

# Check for admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-Not ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Host "Please run this script with admin privileges" -ForegroundColor Red -BackgroundColor Black
    Exit
}

# Make the OTS data folder
if (-Not (Test-Path -Path $DATA_DIR)) {
    New-Item -ItemType Directory -Path $DATA_DIR
    New-Item -ItemType Directory -Path $DATA_DIR\mediamtx
    New-Item -ItemType Directory -Path $DATA_DIR\mediamtx\recordings
}

if (-Not (Test-Path -Path $DATA_DIR\ots.db)) {
    Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/iconsets.sqlite -OutFile $DATA_DIR\ots.db
}

Write-Host "Installing Chocolatey..." -ForegroundColor Green -BackgroundColor Black
# https://chocolatey.org/install#individual
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Write-Host "Installing prerequisites..." -ForegroundColor Green -BackgroundColor Black
choco install python3 openssl rabbitmq nginx sed -y

# Need this so the openssl pkcs12 -legacy option works
[Environment]::SetEnvironmentVariable("OPENSSL_MODULES", "C:\Program Files\OpenSSL-Win64\bin", "Machine")

Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv

Set-Location -Path $DATA_DIR
python -m venv .venv
.\.venv\Scripts\activate
pip install https://github.com/brian7704/OpenTAKServer-Installer/raw/master/unishox2_py3-1.0.0-cp312-cp312-win_amd64.whl
pip install opentakserver

Write-Host "Initializing Database..." -ForegroundColor Green -BackgroundColor Black
Set-Location -Path $DATA_DIR\.venv\lib\python3.*\site-packages\opentakserver
opentakserver.exe --upgrade-db
Set-Location -Path $DATA_DIR
Write-Host "Finished initializing database!" -ForegroundColor Green -BackgroundColor Black

Write-Host "Creating Certificate Authority..." -ForegroundColor Green -BackgroundColor Black
Set-Location -Path $DATA_DIR
.\.venv\bin\opentakserver.exe --create-ca
Write-Host "Finished creating the certificate authority!" -ForegroundColor Green -BackgroundColor Black

Write-Host "Installing MediaMTX.." -ForegroundColor Green -BackgroundColor Black
$url = lastversion --filter '~*windows' --assets bluenviron/mediamtx --only 1.6.0
$filename = $url.Split("/")[-1]
lastversion --filter '~*windows' -o $DATA_DIR\mediamtx\$filename --assets download bluenviron/mediamtx
Set-Location $DATA_DIR\mediamtx
Expand-Archive -Path mediamtx*.zip -DestinationPath . -Force
Remove-Item $DATA_DIR\mediamtx\mediamtx.yml -Force
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/mediamtx.yml -OutFile $DATA_DIR\mediamtx\mediamtx.yml

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
nssm install OpenTAKServer $DATA_DIR\.venv\Scripts\opentakserver.exe
nssm set OpenTAKServer ObjectName $Env:UserDomain\$Env:UserName $password
nssm set OpenTAKServer AppStdout $DATA_DIR\service_stdout.log
nssm set OpenTAKServer AppStderr $DATA_DIR\service_stderr.log
nssm start OpenTAKServer

Write-Host "Starting MediaMTX..." -ForegroundColor Green -BackgroundColor Black
nssm start MediaMTX

Write-Host "Configuring Nginx..." -ForegroundColor Green -BackgroundColor Black

# Get the installed version of nginx
Set-Location -Path C:\tools\nginx*
$version = $pwd.Path.Split("-")[-1]

# Get nginx configs
if (-Not(Test-Path -Path c:\tools\nginx-$version\conf\ots)) {
    New-Item -ItemType Directory -Path c:\tools\nginx-$version\conf\ots
}
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/windows_nginx_configs/nginx.conf -OutFile c:\tools\nginx-$version\conf\nginx.conf
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/windows_nginx_configs/proxy_params -OutFile c:\tools\nginx-$version\conf\proxy_params
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/windows_nginx_configs/ots_http.conf -OutFile c:\tools\nginx-$version\conf\ots\ots_http.conf
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/windows_nginx_configs/ots_https.conf -OutFile c:\tools\nginx-$version\conf\ots\ots_https.conf
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/windows_nginx_configs/ots_certificate_enrollment.conf -OutFile c:\tools\nginx-$version\conf\ots\ots_certificate_enrollment.conf

if (-Not (Test-Path -Path c:\tools\nginx-$version\conf\ots\streams)) {
    New-Item -ItemType Directory -Path c:\tools\nginx-$version\conf\ots\streams
}

Write-Host "Configuring RabbitMQ..." -ForegroundColor Green -BackgroundColor Black
Invoke-WebRequest https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/nginx_configs/rabbitmq -OutFile c:\tools\nginx-$version\conf\ots\streams\rabbitmq.conf
Set-Location -Path "C:\Program Files\RabbitMQ*\rabbitmq_server*\sbin"
.\rabbitmq-plugins.bat enable rabbitmq_mqtt
.\rabbitmq-plugins.bat enable rabbitmq_auth_backend_http
nssm restart rabbitmq

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

sed -i s/SERVER_CERT_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.pem/g c:\tools\nginx-$version\conf\ots\streams\rabbitmq.conf
sed -i s/SERVER_KEY_FILE/$DATA_DIR\\ca\\certs\\opentakserver\\opentakserver.nopass.key/g c:\tools\nginx-$version\conf\ots\streams\rabbitmq.conf

Set-Location -Path $INSTALLER_DIR

nssm restart nginx

Write-Host "Installing OpenTAKServer-UI..." -ForegroundColor Green -BackgroundColor Black
if (-Not (Test-Path -Path c:\tools\nginx-$version\html\opentakserver))  {
    New-Item -ItemType Directory -Path c:\tools\nginx-$version\html\opentakserver
}
Set-Location -Path c:\tools\nginx-$version\html\opentakserver
lastversion --assets extract brian7704/OpenTAKServer-UI

# Get out of the python venv
deactivate

Write-Host "Installation Complete!" -ForegroundColor Green -BackgroundColor Black
# salt installer

$saltDir = "c:\salt"
$saltConfDir = Join-Path $saltDir "conf"
$saltPkiDir = Join-Path $saltConfDir "pki"
$saltPkiMinionDir = Join-Path $saltPkiDir "minion"

$saltMaster = "naci.routedlogic.net"
$saltMinionURL = "https://files.routedlogic.net/salt/bootstrap/salt-minion-setup.exe"
$saltMinionConfigURL = "https://files.routedlogic.net/salt/bootstrap/minion"
$saltMinionMasterSignURL = "https://files.routedlogic.net/salt/bootstrap/master_sign.pub"

if ($env:TEMP -eq $null) {
  $env:TEMP = Join-Path $env:SystemDrive 'temp'
}

if (![System.IO.Directory]::Exists('c:\tmp')) {[System.IO.Directory]::CreateDirectory('c:\tmp')}

if (Test-Path "c:\tmp\minion") { Remove-Item -Path "c:\tmp\minion" -Force }
if (Test-Path "c:\tmp\master_sign.pub") { Remove-Item -Path "c:\tmp\master_sign.pub" -Force }
if (Test-Path "c:\tmp\salt-minion.exe") { Remove-Item -Path "c:\tmp\salt-minion.exe" -Force }

if (![System.IO.Directory]::Exists($saltDir)) {[System.IO.Directory]::CreateDirectory($saltDir)}
if (![System.IO.Directory]::Exists($saltConfDir)) {[System.IO.Directory]::CreateDirectory($saltConfDir)}
if (![System.IO.Directory]::Exists($saltPkiDir)) {[System.IO.Directory]::CreateDirectory($saltPkiDir)}
if (![System.IO.Directory]::Exists($saltPkiMinionDir)) {[System.IO.Directory]::CreateDirectory($saltPkiMinionDir)}

# PowerShell v2/3 caches the output stream. Then it throws errors due^M# to the FileStream not being what is expected. Fixes "The OS handle's^M# position is not what FileStream expected. Do not use a handle^M# simultaneously in one FileStream and in Win32 code or another^M# FileStream."
function Fix-PowerShellOutputRedirectionBug {
  $poshMajorVerion = $PSVersionTable.PSVersion.Major

  if ($poshMajorVerion -lt 4) {
    try{
      # http://www.leeholmes.com/blog/2008/07/30/workaround-the-os-handles-position-is-not-what-filestream-expected/ plus comments
      $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetField"
      $objectRef = $host.GetType().GetField("externalHostRef", $bindingFlags).GetValue($host)
      $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetProperty"
      $consoleHost = $objectRef.GetType().GetProperty("Value", $bindingFlags).GetValue($objectRef, @())
      [void] $consoleHost.GetType().GetProperty("IsStandardOutputRedirected", $bindingFlags).GetValue($consoleHost, @())
      $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetField"
      $field = $consoleHost.GetType().GetField("standardOutputWriter", $bindingFlags)
      $field.SetValue($consoleHost, [Console]::Out)
      [void] $consoleHost.GetType().GetProperty("IsStandardErrorRedirected", $bindingFlags).GetValue($consoleHost, @())
      $field2 = $consoleHost.GetType().GetField("standardErrorWriter", $bindingFlags)
      $field2.SetValue($consoleHost, [Console]::Error)
    } catch {
      Write-Output "Unable to apply redirection fix."
    }
  }
}

Fix-PowerShellOutputRedirectionBug

# Attempt to set highest encryption available for SecurityProtocol.
# PowerShell will not set this by default (until maybe .NET 4.6.x). This
# will typically produce a message for PowerShell v2 (just an info
# message though)
try {
  # Set TLS 1.2 (3072), then TLS 1.1 (768), then TLS 1.0 (192), finally SSL 3.0 (48)
  # Use integers because the enumeration values for TLS 1.2 and TLS 1.1 won't
  # exist in .NET 4.0, even though they are addressable if .NET 4.5+ is
  # installed (.NET 4.5 is an in-place upgrade).
  [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192 -bor 48
} catch {
  Write-Output 'Unable to set PowerShell to use TLS 1.2 and TLS 1.1 due to old .NET Framework installed. If you see underlying connection closed or trust errors, you may need to do one or more of the following: (1) upgrade to .NET Framework 4.5+ and PowerShell v3, (2) specify internal Salt Stack Minion location (set $env:saltyMinionDownloadUrl prior to install or host the package internally), (3) use the Download + PowerShell method of install.'
}

function Get-Downloader {
param (
  [string]$url
 )

  $downloader = new-object System.Net.WebClient

  $defaultCreds = [System.Net.CredentialCache]::DefaultCredentials
  if ($defaultCreds -ne $null) {
    $downloader.Credentials = $defaultCreds
  }

  $ignoreProxy = $env:saltyIgnoreProxy
  if ($ignoreProxy -ne $null -and $ignoreProxy -eq 'true') {
    Write-Debug "Explicitly bypassing proxy due to user environment variable"
    $downloader.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
  } else {
    # check if a proxy is required
    $explicitProxy = $env:saltyProxyLocation
    $explicitProxyUser = $env:saltyProxyUser
    $explicitProxyPassword = $env:saltyProxyPassword
    if ($explicitProxy -ne $null -and $explicitProxy -ne '') {
      # explicit proxy
      $proxy = New-Object System.Net.WebProxy($explicitProxy, $true)
      if ($explicitProxyPassword -ne $null -and $explicitProxyPassword -ne '') {
        $passwd = ConvertTo-SecureString $explicitProxyPassword -AsPlainText -Force
        $proxy.Credentials = New-Object System.Management.Automation.PSCredential ($explicitProxyUser, $passwd)
      }

      Write-Debug "Using explicit proxy server '$explicitProxy'."
      $downloader.Proxy = $proxy

    } elseif (!$downloader.Proxy.IsBypassed($url)) {
      # system proxy (pass through)
      $creds = $defaultCreds
      if ($creds -eq $null) {
        Write-Debug "Default credentials were null. Attempting backup method"
        $cred = get-credential
        $creds = $cred.GetNetworkCredential();
      }

      $proxyaddress = $downloader.Proxy.GetProxy($url).Authority
      Write-Debug "Using system proxy server '$proxyaddress'."
      $proxy = New-Object System.Net.WebProxy($proxyaddress)
      $proxy.Credentials = $creds
      $downloader.Proxy = $proxy
    }
  }

  return $downloader
}

function Download-File {
param (
  [string]$url,
  [string]$file
 )
  Write-Output "Downloading $url to $file"
  $downloader = Get-Downloader $url

  $downloader.DownloadFile($url, $file)
}

Write-Output "Downloading Salt Stack Minion installer."
Download-File $saltMinionURL "c:\tmp\salt-minion.exe"

# Download the Salt Stack Windows Minion configuration files
Write-Output "Getting Salt Minion config files."

# Minion Config
$file = Join-Path $saltConfDir "minion"
if (Test-Path $file) { Remove-Item -Path $file -Force -Recurse }
Download-File $saltMinionConfigURL $file

# Master Signing Key Public Component
$file = Join-Path $saltPkiMinionDir "master_sign.pub"
if (Test-Path $file) { Remove-Item -Path $file -Force -Recurse }
Download-File $saltMasterSignURL $file

# Call Salt Stack Minion installer
Write-Output "Installing Salt Stack Minion on this machine"
c:\tmp\salt-minion.exe /S /minion-name=$env:COMPUTERNAME.$env:USERDNSDOMAIN /start-minion=1

# Restart Salt Stack Minion service
# Restart-Service -Force -Name salt-minion

Start-Sleep -s 10

# EOF

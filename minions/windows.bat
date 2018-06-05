@echo off

REM Variables
SALT_VERSION='2017.7.4'
SALT_VERSION_PY='Py3'
CONFIG_DIR="c:\salt\conf"
MINION_PKI_DIR="c:\salt\conf\pki\minion"

SALT_MINION_SETUP_URL="http://repo.saltstack.com/windows/Salt-Minion-%SALT_VERSION%-%SALT_VERSION_PY%-x86-Setup.exe"
SALT_MINION_CONFIG_URL="http://files.routedlogic.net/salt/bootstrap/minion"
SALT_MASTER_SIGN_PUB_URL="http://files.routedlogic.net/salt/bootstrap/master_sign.pub"

REM Download Salt Minion installer
powershell -Command "Invoke-WebRequest %SALT_MINION_SETUP_URL% -OutFile salt-minion-setup.exe"

REM Download bootstrap Salt Minion config and master signing key
powershell -Command "Invoke-WebRequest %SALT_MINION_CONFIG_URL% -OutFile minion"
powershell -Command "Invoke-WebRequest %SALT_MASTER_SIGN_PUB_URL% -OutFile master_sign.pub"

REM Install Salt Minion silent/unatteneded and ensure minion_id generated correctly
.\salt-minion-setup.exe /S /minion-name=$env:COMPUTERNAME.$env:USERDNSDOMAIN /start-minion=0

REM Install bootstrap minion config and master signing public key from local files
copy /Y minion %CONFIG_DIR%\minion
copy /Y master_sign.pub %MINION_PKI_DIR%\master_sign.pub

REM Re-start Salt Minion
net stop salt-minion
net start salt-minion

REM EOF

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$jdk = Get-ChildItem -Path (Join-Path $projectRoot '.tools\jdk21-extracted') -Directory |
    Select-Object -First 1

if (-not $jdk) {
    throw '프로젝트용 Java 21을 찾을 수 없습니다: .tools\jdk21-extracted'
}

$backendCommand = @"
`$env:JAVA_HOME='$($jdk.FullName)'
`$env:Path="`$env:JAVA_HOME\bin;`$env:Path"
Set-Location '$projectRoot\backend'
.\gradlew.bat bootRun --args="--spring.profiles.active=demo"
"@

$actualFrontend = 'C:\Users\kim30\OneDrive\Desktop\Front-end-main'

$frontendCommand = @"
Set-Location '$actualFrontend'
npm run dev -- --host 127.0.0.1
"@

Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $backendCommand
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $frontendCommand

Write-Host 'AI 보고서 데모를 시작했습니다.'
Write-Host '잠시 후 아래 주소에 접속하세요.'
Write-Host 'http://127.0.0.1:5173/wireframes/%ED%9B%84%EB%B3%B4/B-report.html'

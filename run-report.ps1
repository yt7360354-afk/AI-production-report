# AI 생산 리포트 실행: 백엔드(8080) + 프론트(5174)를 백그라운드로 띄우고 브라우저를 연다.
# 사용: .\run-report.ps1            (JAVA_HOME 또는 PATH의 java 사용)
#       .\run-report.ps1 -JavaHome 'C:\path\to\jdk'
param([string]$JavaHome = $env:JAVA_HOME)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$pageUrl = 'http://127.0.0.1:5174/wireframes/%ED%9B%84%EB%B3%B4/B-report.html'

function Test-Port([int]$port) {
    [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

# 1) 백엔드
if (Test-Port 8080) {
    Write-Host '백엔드(8080)가 이미 실행 중입니다.'
} else {
    if (-not $JavaHome) {
        $local = Get-ChildItem (Join-Path $root '..\.tools\jdk21-extracted') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($local) { $JavaHome = $local.FullName }
    }
    if (-not $JavaHome -and -not (Get-Command java -ErrorAction SilentlyContinue)) {
        throw 'Java(17 이상)를 찾을 수 없습니다. JAVA_HOME을 설정하거나 -JavaHome 으로 JDK 경로를 지정하세요.'
    }
    $javaLine = if ($JavaHome) { "`$env:JAVA_HOME='$JavaHome'; `$env:Path=`"$JavaHome\bin;`$env:Path`";" } else { '' }
    $cmd = "$javaLine Set-Location '$root\backend'; .\gradlew.bat bootRun *> '$logs\backend.log'"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd
    Write-Host '백엔드를 시작했습니다. (로그: logs\backend.log)'
}

# 2) 프론트
if (Test-Port 5174) {
    Write-Host '프론트(5174)가 이미 실행 중입니다.'
} else {
    if (-not (Test-Path (Join-Path $root 'frontend\node_modules'))) {
        Write-Host '프론트 의존성을 설치합니다 (npm install)...'
        Push-Location (Join-Path $root 'frontend'); npm install; Pop-Location
    }
    $cmd = "Set-Location '$root\frontend'; npm run dev *> '$logs\frontend.log'"
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd
    Write-Host '프론트를 시작했습니다. (로그: logs\frontend.log)'
}

# 3) 준비될 때까지 대기 (최대 3분) 후 브라우저 열기
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline -and -not ((Test-Port 8080) -and (Test-Port 5174))) { Start-Sleep -Seconds 2 }
if ((Test-Port 8080) -and (Test-Port 5174)) {
    Start-Process $pageUrl
    Write-Host "준비 완료: $pageUrl"
} else {
    Write-Warning "3분 안에 서버가 준비되지 않았습니다. logs 폴더의 로그를 확인하세요. (백엔드 8080: $(Test-Port 8080), 프론트 5174: $(Test-Port 5174))"
}

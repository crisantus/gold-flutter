$ErrorActionPreference = "Stop"
$repositoryUrl = "https://github.com/crisantus/gold-flutter.git"

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
  throw "Dart was not found. Install Flutter first: https://docs.flutter.dev/get-started/install"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git was not found. Install Git and run this installer again."
}

dart pub global activate --source git $repositoryUrl

Write-Host ""
Write-Host "Gold Flutter is installed."
Write-Host "Run: gold_flutter doctor"
Write-Host "Then move to a parent folder and run: gold_flutter create"
Write-Host ""
Write-Host "If gold_flutter is not found, add %LOCALAPPDATA%\Pub\Cache\bin to PATH."


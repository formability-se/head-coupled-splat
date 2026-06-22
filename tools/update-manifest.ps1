# Regenerate manifest.json from the R2 bucket contents.
#
# Lists all .rad files in r2:head-coupled-splat, writes manifest.json with one
# entry per file, then uploads the manifest back to the bucket. The viewer
# reads {base}/manifest.json on load to populate its example-splats dropdown.
#
# Optional: edit MANIFEST_PATH locally first to set custom labels, then run
# this script with -SkipUpload to write only.
#
# Usage:
#   .\tools\update-manifest.ps1           # list, write, upload
#   .\tools\update-manifest.ps1 -Open     # also opens the resulting JSON
#   .\tools\update-manifest.ps1 -SkipUpload

param(
  [string]$Bucket = "head-coupled-splat",
  [string]$Remote = "r2",
  [string]$Out = "manifest.json",
  [switch]$Open,
  [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"

# Get bucket contents as JSON
Write-Host "Listing $Remote`:$Bucket ..."
$listJson = & rclone lsjson "$Remote`:$Bucket" --files-only
if ($LASTEXITCODE -ne 0) { throw "rclone lsjson failed" }

$entries = $listJson | ConvertFrom-Json | Where-Object {
  $_.Name -match '\.rad$' -and $_.Name -ne $Out
} | Sort-Object Name

if (-not $entries) {
  Write-Warning "No .rad files found in bucket. Manifest will be empty."
}

function Format-Size($bytes) {
  if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
  if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
  if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
  return "$bytes B"
}

$splats = @($entries | ForEach-Object {
  [PSCustomObject]@{
    file  = $_.Name
    size  = $_.Size
    label = "$($_.Name -replace '\.rad$','' -replace '[_-]+',' ')  ($(Format-Size $_.Size))"
  }
})

$manifest = [PSCustomObject]@{
  generated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ").ToString()
  splats    = $splats
}

$json = $manifest | ConvertTo-Json -Depth 5
$jsonPath = Join-Path (Get-Location) $Out
Set-Content -Path $jsonPath -Value $json -Encoding utf8

Write-Host "Wrote $jsonPath ($($splats.Count) entries)"

if ($Open) {
  Get-Content $jsonPath
}

if (-not $SkipUpload) {
  Write-Host "Uploading manifest.json to $Remote`:$Bucket/ ..."
  & rclone copy $jsonPath "$Remote`:$Bucket/" --s3-no-check-bucket --progress
  if ($LASTEXITCODE -ne 0) { throw "rclone copy failed" }
  Write-Host "Done. Viewer will see updated list on next page load."
}

function New-NinjaHealthReport {
    <#
    .SYNOPSIS
        Generates a self-contained single-file HTML report from audit findings.
        No external dependencies - all CSS and JS are inlined.
    #>
    # System.Web required for HtmlEncode - explicitly load to ensure availability on minimal PS 5.1
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    if (-not ([System.Management.Automation.PSTypeName]'System.Web.HttpUtility').Type) {
        throw 'System.Web assembly failed to load. HTML report cannot be generated.'
    }

    param (
        [Parameter(Mandatory)] [array]$Findings,
        [Parameter(Mandatory)] [string]$BaseUrl,
        [string]$ExportPath
    )
    # Fallback output directory when ExportPath is not specified. Defaults to caller's working directory.
    $scriptDir = $PWD.Path

    $severityColors = @{
        Critical = '#dc3545'
        Warning  = '#fd7e14'
        Info     = '#0d6efd'
    }

    $criticalCount = ($Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
    $warningCount = ($Findings | Where-Object { $_.Severity -eq 'Warning' }).Count
    $infoCount = ($Findings | Where-Object { $_.Severity -eq 'Info' }).Count

    # Group findings by Category to build one table section per category
    $grouped = $Findings | Group-Object -Property Category

    $categorySections = foreach ($group in $grouped) {
        $rows = foreach ($f in $group.Group) {
            $color = $severityColors[$f.Severity]
            $badge = "<span style='background:$color;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.8em;'>$($f.Severity)</span>"
            $expandId = "items_$([System.Guid]::NewGuid().ToString('N'))"

            $affectedHtml = ''
            if ($f.AffectedItems -and $f.AffectedItems.Count -gt 0) {
                $listItems = ($f.AffectedItems | ForEach-Object { "<li>$([System.Web.HttpUtility]::HtmlEncode($_))</li>" }) -join ''
                $affectedHtml = "<br><button type='button' onclick=""var e=document.getElementById('$expandId');e.style.display=e.style.display==='none'?'block':'none';"" style='font-size:0.85em;background:none;border:none;padding:0;color:#0d6efd;cursor:pointer;'>Toggle $($f.AffectedCount) affected items</button><ul id='$expandId' style='display:none;margin-top:6px;padding-left:20px;'>$listItems</ul>"
            }

            "<tr><td>$badge</td><td><strong>$([System.Web.HttpUtility]::HtmlEncode($f.Title))</strong><br><span style='color:#6c757d;font-size:0.9em;'>$([System.Web.HttpUtility]::HtmlEncode($f.Detail))</span>$affectedHtml</td><td style='text-align:center;'>$($f.AffectedCount)</td></tr>"
        }

        @"
<div class="card">
  <div class="card-header">$([System.Web.HttpUtility]::HtmlEncode($group.Name))</div>
  <table>
    <thead><tr><th style="width:110px;">Severity</th><th>Finding</th><th style="width:80px;text-align:center;">Affected</th></tr></thead>
    <tbody>$($rows -join '')</tbody>
  </table>
</div>
"@
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NinjaOne Instance Health Audit</title>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; background: #f4f6f9; color: #212529; }
  .header { background: #1a1f36; color: #fff; padding: 24px 32px; }
  .header h1 { margin: 0 0 4px; font-size: 1.6em; font-weight: 600; }
  .header p  { margin: 0; color: #a0aec0; font-size: 0.9em; }
  .container { max-width: 1100px; margin: 32px auto; padding: 0 16px; }
  .scorecard { display: flex; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }
  .stat-card { flex: 1; min-width: 140px; background: #fff; border-radius: 8px; padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.1); text-align: center; }
  .stat-card .count { font-size: 2.4em; font-weight: 700; line-height: 1; }
  .stat-card .label { font-size: 0.85em; color: #6c757d; margin-top: 4px; }
  .card { background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,.1); margin-bottom: 20px; overflow: hidden; }
  .card-header { background: #f8f9fa; border-bottom: 1px solid #dee2e6; padding: 12px 20px; font-weight: 600; font-size: 1em; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 12px 20px; border-bottom: 1px solid #dee2e6; vertical-align: top; text-align: left; }
  th { background: #f8f9fa; font-size: 0.8em; text-transform: uppercase; letter-spacing: .05em; color: #6c757d; }
  tr:last-child td { border-bottom: none; }
  a { color: #0d6efd; text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
</head>
<body>
<div class="header">
  <h1>NinjaOne Instance Health Audit</h1>
  <p>Instance: $([System.Web.HttpUtility]::HtmlEncode($BaseUrl)) &nbsp;&bull;&nbsp; Generated: $timestamp</p>
</div>
<div class="container">
  <div class="scorecard">
    <div class="stat-card"><div class="count" style="color:$($severityColors.Critical);">$criticalCount</div><div class="label">Critical</div></div>
    <div class="stat-card"><div class="count" style="color:$($severityColors.Warning);">$warningCount</div><div class="label">Warning</div></div>
    <div class="stat-card"><div class="count" style="color:$($severityColors.Info);">$infoCount</div><div class="label">Info</div></div>
    <div class="stat-card"><div class="count" style="color:#212529;">$($Findings.Count)</div><div class="label">Total Findings</div></div>
  </div>
  $($categorySections -join "`n")
</div>
</body>
</html>
"@

    $outputDir = if ($ExportPath) {
        $ExportPath
    } else {
        $scriptDir
    }
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $fileName = "NinjaAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $outputFile = Join-Path $outputDir $fileName

    [System.IO.File]::WriteAllText($outputFile, $html, [System.Text.UTF8Encoding]::new($false))
    return $outputFile
}

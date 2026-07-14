<#
  add_analytics.ps1
  -----------------
  Injects the Google Analytics 4 (gtag.js) snippet into every public page of
  the Rexford site, immediately after the opening <head> tag.

  Idempotent: the injected block is delimited by <!-- GA:BEGIN --> / <!-- GA:END -->.
  Re-running replaces the block rather than duplicating it, so this is safe to
  run after any content change or measurement-ID change.

  Run from the repo root:  powershell -File tools\add_analytics.ps1
#>

$ErrorActionPreference = 'Stop'

# GA4 measurement ID for the rexfordco.ca property.
$MeasurementId = 'G-X0FYHZWVTZ'

# Internal pages: never published / noindex, so never tracked.
$Skip = @('_mockup.html', 'summer-job-agreement.html')

$Snippet = @"
<!-- GA:BEGIN -->
  <!-- Google tag (gtag.js) -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=$MeasurementId"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', '$MeasurementId');

    // Phone / email clicks as GA4 events (enhanced measurement skips tel:/mailto:).
    // Marked as key events in GA4 admin; imported as conversions by Google Ads.
    document.addEventListener('click', function (e) {
      var a = e.target.closest ? e.target.closest('a') : null;
      if (!a) return;
      var href = a.getAttribute('href') || '';
      if (href.indexOf('tel:') === 0) {
        gtag('event', 'phone_click', { link_url: href, page_path: location.pathname });
      } else if (href.indexOf('mailto:') === 0) {
        gtag('event', 'email_click', { link_url: href, page_path: location.pathname });
      }
    });
  </script>
  <!-- GA:END -->
"@

$pages = Get-ChildItem -Path (Get-Location) -Filter '*.html' | Where-Object { $Skip -notcontains $_.Name }

foreach ($p in $pages) {
    $html = [System.IO.File]::ReadAllText($p.FullName)

    if ($html -match '(?s)<!-- GA:BEGIN -->.*?<!-- GA:END -->') {
        # Replace the existing block (ID change or snippet update).
        $html = [regex]::Replace($html, '(?s)<!-- GA:BEGIN -->.*?<!-- GA:END -->', $Snippet)
        $action = 'updated'
    }
    elseif ($html -match '(?i)<head>') {
        $html = [regex]::Replace($html, '(?i)<head>', "<head>`n  $Snippet", 1)
        $action = 'added'
    }
    else {
        Write-Warning "$($p.Name): no <head> tag found, skipped"
        continue
    }

    [System.IO.File]::WriteAllText($p.FullName, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "$action  $($p.Name)"
}

<#
  add_seo_metadata.ps1
  --------------------
  Injects canonical + Open Graph + Twitter + JSON-LD structured data into every
  public page of the Rexford site, and regenerates robots.txt and sitemap.xml.

  Idempotent: the injected block is delimited by <!-- SEO:BEGIN --> / <!-- SEO:END -->.
  Re-running replaces the block rather than duplicating it, so this is safe to run
  after any content change.

  All facts (address, phone, roles, post dates) are read from the pages themselves.
  Nothing is invented. Run from the repo root:  powershell -File tools\add_seo_metadata.ps1
#>

$ErrorActionPreference = 'Stop'

$Base    = 'https://rexfordco.ca'
$OgImage = "$Base/Marketing/website-photos/interior-kitchen-1.jpeg"
$Logo    = "$Base/Brand%20Asset/R.png"
$BizName = 'Rexford Contracting & Design Inc.'
$BizId   = "$Base/#business"
$SiteId  = "$Base/#website"

# Pages that must never be indexed (internal docs / scratch)
$NoIndex = @('summer-job-agreement.html')
$Skip    = @('_mockup.html')

function Get-Tag {
    param($Html, $Pattern)
    $m = [regex]::Match($Html, $Pattern, 'Singleline')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
function Decode { param($s) [System.Net.WebUtility]::HtmlDecode($s) }
function AttrEsc { param($s) [System.Net.WebUtility]::HtmlEncode($s) }

# Canonical URL: vercel.json sets cleanUrls=true, so pages are served without .html
function Get-Canonical {
    param($FileName)
    if ($FileName -eq 'index.html') { return "$Base/" }
    return "$Base/" + ($FileName -replace '\.html$','')
}

# "Design &middot; June 2026" -> 2026-06-01
function Get-PostDate {
    param($Html)
    $months = @{january='01';february='02';march='03';april='04';may='05';june='06'
                july='07';august='08';september='09';october='10';november='11';december='12'}
    $m = [regex]::Match($Html, 'class="post-eyebrow">([^<]+)<')
    if (-not $m.Success) { return $null }
    $txt = Decode $m.Groups[1].Value
    $d = [regex]::Match($txt, '([A-Za-z]+)\s+(\d{4})')
    if (-not $d.Success) { return $null }
    $mon = $d.Groups[1].Value.ToLower()
    if (-not $months.ContainsKey($mon)) { return $null }
    return "$($d.Groups[2].Value)-$($months[$mon])-01"
}

function To-Json { param($Obj) ($Obj | ConvertTo-Json -Depth 12 -Compress) }

# The seven services shown in the homepage ticker
$Services = @('Site Planning','Drafting','Custom Homes','Renovations',
              'Multi-family','Commercial','Interior Design')

$Publisher = [ordered]@{ '@id' = $BizId }

# ---------------------------------------------------------------- business node
$BusinessNode = [ordered]@{
    '@type'       = 'ProfessionalService'
    '@id'         = $BizId
    'name'        = $BizName
    'alternateName' = 'Rexford'
    'url'         = "$Base/"
    'logo'        = $Logo
    'image'       = $OgImage
    'telephone'   = '+1-778-808-6397'
    'email'       = 'info@rexfordco.ca'
    'priceRange'  = '$$'
    'address'     = [ordered]@{
        '@type'           = 'PostalAddress'
        'streetAddress'   = '8465 Harvard Pl #16'
        'addressLocality' = 'Chilliwack'
        'addressRegion'   = 'BC'
        'postalCode'      = 'V2P 7Z5'
        'addressCountry'  = 'CA'
    }
    'areaServed'  = @(
        [ordered]@{ '@type'='AdministrativeArea'; 'name'='British Columbia' },
        [ordered]@{ '@type'='AdministrativeArea'; 'name'='Alberta' }
    )
    'sameAs'      = @('https://instagram.com/therexfordcompany')
    'hasOfferCatalog' = [ordered]@{
        '@type' = 'OfferCatalog'
        'name'  = 'Design & Drafting Services'
        'itemListElement' = @(
            $Services | ForEach-Object {
                [ordered]@{ '@type'='Offer'; 'itemOffered'=[ordered]@{ '@type'='Service'; 'name'=$_ } }
            }
        )
    }
}

$WebSiteNode = [ordered]@{
    '@type'     = 'WebSite'
    '@id'       = $SiteId
    'url'       = "$Base/"
    'name'      = 'Rexford'
    'publisher' = $Publisher
    'inLanguage'= 'en-CA'
}

# ---------------------------------------------------------------- page loop
$pages = Get-ChildItem -Filter '*.html' -File | Where-Object { $Skip -notcontains $_.Name } | Sort-Object Name
$sitemapEntries = @()
$report = @()

foreach ($p in $pages) {
    $name = $p.Name
    $html = [System.IO.File]::ReadAllText($p.FullName)

    # strip any previously-injected block so this stays idempotent
    $html = [regex]::Replace($html, '(?s)\s*<!-- SEO:BEGIN -->.*?<!-- SEO:END -->', '')

    $rawTitle = Get-Tag $html '<title>(.*?)</title>'
    $rawDesc  = Get-Tag $html '<meta name="description" content="(.*?)"'
    $title    = Decode $rawTitle
    $desc     = Decode $rawDesc
    $canon    = Get-Canonical $name

    # ---- noindex pages: robots meta only, no OG/schema, not in sitemap
    if ($NoIndex -contains $name) {
        $block = "  <!-- SEO:BEGIN -->`n  <meta name=""robots"" content=""noindex, nofollow"">`n  <!-- SEO:END -->`n"
        $html  = $html -replace '(?i)</head>', "$block</head>"
        [System.IO.File]::WriteAllText($p.FullName, $html, (New-Object System.Text.UTF8Encoding($false)))
        $report += [pscustomobject]@{ Page=$name; Type='noindex'; Schema='-' }
        continue
    }

    # ---- classify page
    $schemaNode = $null
    $ogType = 'website'
    $type   = 'page'

    if ($name -eq 'index.html') {
        $type = 'home'
        $schemaNode = @($BusinessNode, $WebSiteNode)
    }
    elseif ($name -like 'blog-*') {
        $type = 'blogpost'; $ogType = 'article'
        $headline = ($title -replace '\s*-\s*REXFORD Journal\s*$','').Trim()
        $node = [ordered]@{
            '@type'            = 'BlogPosting'
            'headline'         = $headline
            'description'      = $desc
            'url'              = $canon
            'mainEntityOfPage' = $canon
            'image'            = $OgImage
            'inLanguage'       = 'en-CA'
            'author'           = [ordered]@{ '@type'='Organization'; 'name'=$BizName; '@id'=$BizId }
            'publisher'        = $Publisher
        }
        $pd = Get-PostDate $html
        if ($pd) { $node['datePublished'] = $pd }
        $schemaNode = @($node)
    }
    elseif ($name -eq 'blog.html') {
        $type = 'blogindex'
        $schemaNode = @([ordered]@{
            '@type'='Blog'; 'name'='Rexford Journal'; 'url'=$canon
            'description'=$desc; 'publisher'=$Publisher; 'inLanguage'='en-CA'
        })
    }
    elseif ($name -like 'team-*') {
        $type = 'person'; $ogType = 'profile'
        $role = Decode (Get-Tag $html 'class="profile-role">(.*?)<')
        $pname = Decode (Get-Tag $html 'class="profile-name"[^>]*>(.*?)</h1>')
        $pname = ($pname -replace '<br\s*/?>',' ' -replace '\s+',' ').Trim()
        $node = [ordered]@{
            '@type'    = 'Person'
            'name'     = $pname
            'url'      = $canon
            'worksFor' = [ordered]@{ '@type'='Organization'; 'name'=$BizName; '@id'=$BizId }
        }
        if ($role) { $node['jobTitle'] = $role }
        $schemaNode = @($node)
    }
    elseif ($name -in @('services.html','drafting.html')) {
        $type = 'service'
        $schemaNode = @([ordered]@{
            '@type'       = 'Service'
            'name'        = ($title -replace '\s*[-—]\s*REXFORD\s*$','').Trim()
            'description' = $desc
            'url'         = $canon
            'provider'    = $Publisher
            'areaServed'  = @(
                [ordered]@{ '@type'='AdministrativeArea'; 'name'='British Columbia' },
                [ordered]@{ '@type'='AdministrativeArea'; 'name'='Alberta' }
            )
            'hasOfferCatalog' = [ordered]@{
                '@type'='OfferCatalog'; 'name'='Services'
                'itemListElement' = @($Services | ForEach-Object {
                    [ordered]@{ '@type'='Offer'; 'itemOffered'=[ordered]@{ '@type'='Service'; 'name'=$_ } }
                })
            }
        })
    }
    else {
        $schemaNode = @([ordered]@{
            '@type'='WebPage'; 'name'=$title; 'description'=$desc; 'url'=$canon
            'isPartOf'=[ordered]@{ '@id'=$SiteId }; 'about'=$Publisher; 'inLanguage'='en-CA'
        })
    }

    $graph = [ordered]@{ '@context'='https://schema.org'; '@graph'=$schemaNode }
    $json  = To-Json $graph

    $tTitle = AttrEsc $title
    $tDesc  = AttrEsc $desc

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('  <!-- SEO:BEGIN -->')
    [void]$sb.AppendLine("  <link rel=""canonical"" href=""$canon"">")
    [void]$sb.AppendLine("  <meta property=""og:type"" content=""$ogType"">")
    [void]$sb.AppendLine("  <meta property=""og:site_name"" content=""Rexford"">")
    [void]$sb.AppendLine("  <meta property=""og:locale"" content=""en_CA"">")
    [void]$sb.AppendLine("  <meta property=""og:url"" content=""$canon"">")
    [void]$sb.AppendLine("  <meta property=""og:title"" content=""$tTitle"">")
    [void]$sb.AppendLine("  <meta property=""og:description"" content=""$tDesc"">")
    [void]$sb.AppendLine("  <meta property=""og:image"" content=""$OgImage"">")
    [void]$sb.AppendLine("  <meta name=""twitter:card"" content=""summary_large_image"">")
    [void]$sb.AppendLine("  <meta name=""twitter:title"" content=""$tTitle"">")
    [void]$sb.AppendLine("  <meta name=""twitter:description"" content=""$tDesc"">")
    [void]$sb.AppendLine("  <meta name=""twitter:image"" content=""$OgImage"">")
    [void]$sb.AppendLine("  <script type=""application/ld+json"">")
    [void]$sb.AppendLine("  $json")
    [void]$sb.AppendLine('  </script>')
    [void]$sb.AppendLine('  <!-- SEO:END -->')

    $html = $html -replace '(?i)</head>', ($sb.ToString() + '</head>')
    [System.IO.File]::WriteAllText($p.FullName, $html, (New-Object System.Text.UTF8Encoding($false)))

    # lastmod from git history (real data, not invented)
    $lastmod = (& git log -1 --format=%cs -- $name 2>$null)
    if (-not $lastmod) { $lastmod = (Get-Date -Format 'yyyy-MM-dd') }
    $priority = switch ($type) { 'home' {'1.0'} 'service' {'0.9'} 'blogpost' {'0.7'} 'person' {'0.5'} default {'0.6'} }
    $sitemapEntries += [pscustomobject]@{ Url=$canon; LastMod=$lastmod; Priority=$priority }

    $report += [pscustomobject]@{ Page=$name; Type=$type; Schema=($schemaNode | ForEach-Object { $_['@type'] }) -join '+' }
}

# ---------------------------------------------------------------- sitemap.xml
$sm = New-Object System.Text.StringBuilder
[void]$sm.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sm.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
$sorted = $sitemapEntries | Sort-Object @{Expression={[double]$_.Priority}; Descending=$true}, @{Expression={$_.Url}; Descending=$false}
foreach ($e in $sorted) {
    [void]$sm.AppendLine('  <url>')
    [void]$sm.AppendLine("    <loc>$($e.Url)</loc>")
    [void]$sm.AppendLine("    <lastmod>$($e.LastMod)</lastmod>")
    [void]$sm.AppendLine("    <priority>$($e.Priority)</priority>")
    [void]$sm.AppendLine('  </url>')
}
[void]$sm.AppendLine('</urlset>')
[System.IO.File]::WriteAllText((Join-Path (Get-Location) 'sitemap.xml'), $sm.ToString(), (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- robots.txt
# Named AI crawlers are listed explicitly and allowed. Default behaviour without a
# robots.txt is "allow", but naming them is a deliberate, readable signal -- and it
# means a future tightening only needs one line changed per bot.
$aiBots = @('GPTBot','OAI-SearchBot','ChatGPT-User','ClaudeBot','Claude-User','anthropic-ai',
            'PerplexityBot','Perplexity-User','Google-Extended','Applebot','Applebot-Extended',
            'Bingbot','CCBot','meta-externalagent','Amazonbot','DuckAssistBot','cohere-ai')

$rb = New-Object System.Text.StringBuilder
[void]$rb.AppendLine('# robots.txt - rexfordco.ca')
[void]$rb.AppendLine('# Search and AI assistants are welcome. Internal documents are excluded.')
[void]$rb.AppendLine('')
[void]$rb.AppendLine('User-agent: *')
[void]$rb.AppendLine('Allow: /')
[void]$rb.AppendLine('Disallow: /summer-job-agreement')
[void]$rb.AppendLine('Disallow: /_mockup')
[void]$rb.AppendLine('')
[void]$rb.AppendLine('# --- AI / LLM crawlers: explicitly permitted so Rexford can be cited in AI answers ---')
foreach ($b in $aiBots) {
    [void]$rb.AppendLine('')
    [void]$rb.AppendLine("User-agent: $b")
    [void]$rb.AppendLine('Allow: /')
    [void]$rb.AppendLine('Disallow: /summer-job-agreement')
}
[void]$rb.AppendLine('')
[void]$rb.AppendLine("Sitemap: $Base/sitemap.xml")
[System.IO.File]::WriteAllText((Join-Path (Get-Location) 'robots.txt'), $rb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- report
$report | Format-Table -AutoSize
Write-Host ""
Write-Host "Pages processed : $($report.Count)"
Write-Host "Sitemap URLs    : $($sitemapEntries.Count)"
Write-Host "AI bots allowed : $($aiBots.Count)"

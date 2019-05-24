$ErrorActionPreference = 'Stop'

[System.Collections.Generic.LinkedList[string]] $directories = @("src")

if (Test-Path "$PWD/web") {
	Remove-Item -Recurse -Force "$PWD/web"
}
New-Item -Type Directory "$PWD/web"


# Write blog's Atom feed

New-Item -Type Directory "$PWD/web/blog"
$feedFile = [System.IO.FileStream]::new("$PWD/web/blog/atom.xml", [System.IO.FileMode]::Create)
$feedWriterSettings = [System.Xml.XmlWriterSettings]::new()
$feedWriterSettings.Indent = $true
$feedWriterSettings.IndentChars = "`t"
$feedWriter = [System.Xml.XmlWriter]::Create($feedFile, $feedWriterSettings)

$feed = [System.ServiceModel.Syndication.SyndicationFeed]::new()
$feed.Id = 'https://www.arnavion.dev/blog/atom.xml'
$feed.Title = 'Arnavion''s Blog'

$feedLink = [System.ServiceModel.Syndication.SyndicationLink]::new('https://www.arnavion.dev/blog/atom.xml')
$feedLink.RelationshipType
$feedLink.RelationshipType = 'self'
$feed.Links.Add($feedLink)

$author = [System.ServiceModel.Syndication.SyndicationPerson]::new()
$author.Name = 'Arnavion'
$feed.Authors.Add($author)

Get-ChildItem -Directory "$PWD/src/blog" | %{
	$item =
		[System.ServiceModel.Syndication.SyndicationItem]::new(
			(Get-Content -Raw "$($_.FullName)/title").Trim(),
			'',
			"https://www.arnavion.dev/blog/$($_.Name)/"
		)
	$item.Id = $item.Links[0].Uri
	$item.PublishDate = $item.LastUpdatedTime =
		[System.DateTime]::SpecifyKind(
			[System.DateTime]::ParseExact(
				$_.Name.Substring(0, 'yyyy-MM-dd'.Length),
				'yyyy-MM-dd',
				[System.Globalization.CultureInfo]::InvariantCulture
			),
			[System.DateTimeKind]::Utc
		)
	$feed.Items.Add($item)
}

$feed.SaveAsAtom10($feedWriter)

$feedWriter.Close()


# Generate XHTML pages

for (;;) {
	$directory = $directories.First.Value
	if ($directory -eq $null) {
		break
	}

	$directories.RemoveFirst()

	$outputDirectory = "$($directory -replace '^src', 'web')"

	if (-not (Test-Path "$PWD/$outputDirectory")) {
		New-Item -Type Directory "$PWD/$outputDirectory"
	}

	$content = @"
<?xml version="1.0" encoding="utf-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
	<head>
		<title>$([System.Security.SecurityElement]::Escape((Get-Content -Raw "$PWD/$directory/title").Trim())) - arnavion.dev</title>

"@

	[string[]] $cssUrls = @()

	for ($dir = $directory; $dir -ne '.'; $dir = [System.IO.Path]::GetRelativePath("$PWD", [System.IO.Path]::GetDirectoryName("$PWD/$dir"))) {
		if (Test-Path "$PWD/$dir/index.css") {
			$cssUrls = ([System.IO.Path]::GetRelativePath("$PWD/$directory", "$PWD/$dir/index.css") -replace '\\', '/') + $cssUrls
		}
	}

	foreach ($cssUrl in $cssUrls) {
		$content += @"
		<link rel="stylesheet" href="$cssUrl" />

"@
	}

	if (Test-Path "$PWD/$outputDirectory/atom.xml") {
		$content += @"
		<link rel="alternative" href="./atom.xml" type="application/atom+xml" />

"@
	}

	$content += @"
	</head>
	<body>
		<header>
			<h1>$([System.Security.SecurityElement]::Escape((Get-Content -Raw "$PWD/$directory/title").Trim()))</h1>
		</header>

		<main>
$((Get-Content -Raw "$PWD/$directory/content.xhtml").Trim())
		</main>

		<footer>
			<p>
				Copyright Arnav Singh,
				under the <a rel="license" href="https://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</a>
			</p>
			<p>Source at <a href="https://github.com/Arnavion/www-arnavion-dev">https://github.com/Arnavion/www-arnavion-dev</a></p>
		</footer>
	</body>
</html>
"@

	[System.IO.File]::WriteAllText("$PWD/$outputDirectory/index.xhtml", $content)

	if (Test-Path "$PWD/$directory/index.css") {
		Copy-Item "$PWD/$directory/index.css" "$PWD/$outputDirectory/index.css"
	}

	Get-ChildItem -Directory "$PWD/$directory" | %{
		$directories.AddLast([System.IO.Path]::GetRelativePath("$PWD", $_.FullName))
	}
}

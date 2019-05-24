$ErrorActionPreference = 'Stop'

[System.Collections.Generic.LinkedList[string]] $directories = @("src")

if (Test-Path "$PWD/web") {
	Remove-Item -Recurse -Force "$PWD/web"
}

for (;;) {
	$directory = $directories.First.Value
	if ($directory -eq $null) {
		break
	}

	$directories.RemoveFirst()

	$outputDirectory = "$($directory -replace '^src', 'web')"

	New-Item -Type Directory "$PWD/$outputDirectory"

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

#!/bin/bash

set -euo pipefail

blog_out_dirname() {
	out="$1"
	out="${out#src/blog/}"
	out="${out%.md}"
	printf '%s' "$out"
}

blog_title() {
	trap 'rm -f title.html' RETURN
	printf '$title$' > title.html
	pandoc \
		--fail-if-warnings \
		--output - --to html5 --template title.html \
		--from markdown-smart "$1"
}

blog_pubdate() {
	trap 'rm -f pubdate.html' RETURN
	printf '$date$' > pubdate.html
	date="$(
		pandoc \
		--fail-if-warnings \
		--output - --to html5 --template pubdate.html \
		--from markdown-smart "$1"
	)"
	date -Rud "$date"
}

rm -rf out
mkdir -p out


# CSS
css="$(sassc --style compressed src/style.scss)"


# /index.html
pandoc \
	--fail-if-warnings \
	--output out/index.html --to html5 --template templates/index.html \
	--variable "css:$css" \
	--from markdown-smart src/index.md


# /blog/*/index.html

previous=''
current=''
for next in src/blog/* ''; do
	if [ "$next" == 'src/blog/index.md' ]; then
		continue
	fi

	if [ -n "$current" ]; then
		previous_out=''
		previous_title=''
		if [ -n "$previous" ]; then
			previous_out="$(blog_out_dirname "$previous")"
			previous_title="$(blog_title "$previous")"
		fi

		current_out="$(blog_out_dirname "$current")"

		next_out=''
		next_title=''
		if [ -n "$next" ]; then
			next_out="$(blog_out_dirname "$next")"
			next_title="$(blog_title "$next")"
		fi

		mkdir -p "out/blog/$current_out"
		pandoc \
			--fail-if-warnings \
			--output "out/blog/$current_out/index.html" --to html5 --template templates/blog/post.html \
			--variable "css:$css" \
			--variable "blog_previous_filename:$previous_out" \
			--variable "blog_previous_title:$previous_title" \
			--variable "blog_current_dirname:$current_out" \
			--variable "blog_next_filename:$next_out" \
			--variable "blog_next_title:$next_title" \
			--from markdown-smart+link_attributes "$current"
	fi

	previous="$current"
	current="$next"
done


# /blog/index.html

blog_index_content=''

for current in src/blog/*; do
	if [ "$current" == 'src/blog/index.md' ]; then
		continue
	fi

	current_out="$(blog_out_dirname "$current")"
	current_title="$(blog_title "$current")"

	blog_index_content="$(printf -- '- [%s](%s)\n%s' "$current_title" "/blog/$current_out/" "$blog_index_content")"
done

pandoc \
	--fail-if-warnings \
	--output out/blog/index.html --to html5 --template templates/blog/index.html \
	--variable "css:$css" \
	--from markdown-smart src/blog/index.md <(printf '%s' "$blog_index_content")


# /blog/index.xml

blog_rss_content=''

for current in src/blog/*; do
	if [ "$current" == 'src/blog/index.md' ]; then
		continue
	fi

	current_out="$(blog_out_dirname "$current")"
	current_title="$(blog_title "$current")"

	blog_rss_content="$(
		pandoc \
			--fail-if-warnings \
			--output - --template templates/blog/post.xml \
			--variable "blog_current_dirname:$current_out" \
			--variable "blog_current_pubdate:$(blog_pubdate "$current")" \
			--from markdown-smart "$current"
	)$blog_rss_content"
done

blog_rss_content="<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?>
<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">
	<channel>
		<title>Blog - www.arnavion.dev</title>
		<link>https://www.arnavion.dev/blog/</link>
		<description>Blog - www.arnavion.dev</description>
		<language>en-us</language>
		<lastBuildDate>$(date -Ru)$</lastBuildDate>
		<atom:link href=\"https://www.arnavion.dev/blog/index.xml\" rel=\"self\" type=\"application/rss+xml\" />
$blog_rss_content
	</channel>
</rss>
"
printf '%s' "$blog_rss_content" > out/blog/index.xml

grep -R '<a href="http' out/ | grep -v 'nofollow' | sed -e 's/^/Missing nofollow: /' && exit 1 || :

echo 'OK'


if [ "${1:-}" = 'publish' ]; then
	AZURE_RESOURCE_GROUP_NAME='arnavion-dev'
	AZURE_STORAGE_ACCOUNT_NAME='wwwarnaviondev'
	AZURE_CDN_PROFILE_NAME='arnavion-dev'
	AZURE_CDN_ENDPOINT_NAME='www-arnavion-dev'

	AZURE_STORAGE_ACCOUNT_CONNECTION_STRING="$(
		az storage account show-connection-string \
			--resource-group "$AZURE_RESOURCE_GROUP_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME" \
			--query connectionString --output tsv
	)"

	# Strip trailing newline to match the HTML output
	css_sha256="$(<<< "$css" head -c -1 | openssl dgst -binary -sha256 | base64 -w 0)"

	cdn_endpoint_delivery_policy_rules="$(jq --null-input --compact-output \
		--arg CSP "default-src 'none'; style-src 'sha256-$css_sha256'" \
		'[{
			"order": 1,
			"name": "EnforceHTTPS",
			"conditions": [{
				"name": "RequestScheme",
				"parameters": { "matchValues": ["HTTP"] }
			}],
			"actions": [{
				"name": "UrlRedirect",
				"parameters": {
					"destinationProtocol": "Https",
					"redirectType": "PermanentRedirect"
				}
			}]
		}, {
			"order": 2,
			"name": "AddCSPHeader",
			"conditions": [{
				"name": "RequestUri",
				"parameters": { "operator": "Any", "matchValues": [] }
			}],
			"actions": [{
				"name": "ModifyResponseHeader",
				"parameters": {
					"headerAction": "Append",
					"headerName": "content-security-policy",
					"value": $CSP
				}
			}]
		}]'
	)"

	az storage blob delete-batch \
		--connection-string "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" \
		--source '$web' \
		--verbose

	az storage blob upload-batch \
		--connection-string "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" \
		--source "$PWD/out" --destination '$web' --type block \
		--verbose

	az cdn endpoint update \
		--resource-group "$AZURE_RESOURCE_GROUP_NAME" --profile-name "$AZURE_CDN_PROFILE_NAME" --name "$AZURE_CDN_ENDPOINT_NAME" \
		--set "deliveryPolicy.rules=$cdn_endpoint_delivery_policy_rules"

	az cdn endpoint purge \
		--resource-group "$AZURE_RESOURCE_GROUP_NAME" --profile-name "$AZURE_CDN_PROFILE_NAME" --name "$AZURE_CDN_ENDPOINT_NAME" \
		--content-paths '/*'
fi

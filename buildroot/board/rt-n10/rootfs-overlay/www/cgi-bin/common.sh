# shared by the RT-N10 web pages (busybox httpd CGI)
. /etc/rtn10/defaults
export LC_ALL=C
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
page_head() {
	printf 'Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nX-Frame-Options: DENY\r\n\r\n'
	echo '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
	echo "<title>$1</title><style>body{font-family:sans-serif;max-width:46em;margin:1em auto;padding:0 1em}"
	echo 'pre{background:#eee;padding:.6em;overflow-x:auto}input{margin:.2em 0}</style></head><body>'
}
page_foot() { echo '</body></html>'; }

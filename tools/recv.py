"""The localhost bridge for scrape_wowhead.js: Wowhead's pages can't post to localhost, so the scrape
navigates here with its data (gzip, base64) after the #, and this page posts that back to be saved.

    python3 tools/recv.py [out dir, default tools/data/wowhead]
"""
import base64, gzip, http.server, os, sys, urllib.parse
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "wowhead")
PAGE = b"""<!doctype html><meta charset=utf-8><body>saving...<script>
fetch('/post'+location.search,{method:'POST',body:location.hash.slice(1)}).then(r=>r.text()).then(t=>document.body.textContent=t)
</script>"""
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers(); self.wfile.write(PAGE)
    def do_POST(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = q['name'][0]
        body = self.rfile.read(int(self.headers['Content-Length']))
        data = gzip.decompress(base64.b64decode(urllib.parse.unquote(body.decode())))
        path = os.path.join(OUT, name)
        open(path, 'wb').write(data)
        msg = f"saved {name}: {len(data)} bytes".encode()
        print(msg.decode(), flush=True)
        self.send_response(200); self.end_headers(); self.wfile.write(msg)
http.server.HTTPServer(('127.0.0.1', 18766), H).serve_forever()

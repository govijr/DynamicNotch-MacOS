"""Loopback-only fixtures for downloads, file promises and native upload drops."""
import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import time
import zlib


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    pixels = b"".join(b"\0" + bytes((80, 100 + y, 235, 255)) * 128 for y in range(128))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 128, 128, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


IMAGE = png()
PAYLOAD = b"Notch Browser transfer fixture\n"
VIDEO = Path(__file__).resolve().parents[2] / "nb-web/public/nbdemo.mp4"
PAGE = """<!doctype html><meta charset="utf-8"><title>Notch Browser transfer checks</title>
<style>body{margin:24px;background:#fafafa;color:#222;font:15px -apple-system}
.assets{display:flex;gap:24px;align-items:start}img{border-radius:16px}video{width:260px;height:150px;background:#ddd}
a{display:inline-block;margin:8px 16px 8px 0}#drop{border:2px dashed #888;border-radius:12px;padding:22px;margin-top:18px;min-height:38px}
small{display:block;color:#666;margin:8px 0}</style><h2>File transfers</h2>
<div class="assets"><div><img id="image" src="/transfer.png" width="150" height="150" alt="Transfer test image">
<small>Drag this image to Finder or Icon Composer.</small></div><div><video id="video" src="/transfer.mp4" controls preload="metadata"></video>
<small>Option-drag this video to Finder.</small></div></div>
<div><a id="download" href="/transfer.png" download="notch-check.png">Download image</a>
<a id="attachment" href="/attachment">Server attachment</a>
<a id="unsupported" href="/archive">Unsupported MIME</a>
<a id="blob" href="#">Download blob</a>
<a id="data" href="data:image/png;base64,IMAGE_BASE64" download="notch-data.png">Download data image</a>
<a id="protected" href="/protected" download="notch-protected.txt">Cookie-protected file</a>
<a id="slow" href="/slow" download="notch-slow.bin">Slow download</a>
<a id="failure" href="/failure" download="notch-failure.bin">Failed download</a></div>
<div id="drop">Drop images/videos here — files stay on this Mac.</div>
<p><input id="upload" type="file" multiple accept="image/*,video/*"></p><pre id="result"></pre>
<script>
document.cookie='transfer_auth=1; path=/; SameSite=Strict';
const result=document.getElementById('result'), drop=document.getElementById('drop');
function report(files){result.textContent=Array.from(files).map(f=>f.name+' · '+f.size+' bytes · '+f.type).join('\\n')}
drop.addEventListener('dragover',e=>{e.preventDefault();e.dataTransfer.dropEffect='copy'});
drop.addEventListener('drop',e=>{e.preventDefault();report(e.dataTransfer.files)});
document.getElementById('upload').addEventListener('change',e=>report(e.target.files));
document.getElementById('blob').onclick=e=>{e.preventDefault();const a=document.createElement('a');
a.href=URL.createObjectURL(new Blob(['Notch Browser blob fixture\\n'],{type:'text/plain'}));a.download='notch-blob.txt';a.click()};
</script>""".replace("IMAGE_BASE64", base64.b64encode(IMAGE).decode()).encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/":
            return self.respond(PAGE, "text/html")
        if route == "/session-fixture":
            return self.respond(b'<!doctype html><title>Cookie observer fixture</title><p>Local cookie fixture</p>', "text/html")
        if route == "/transfer.png":
            return self.respond(IMAGE, "image/png")
        if route == "/transfer.mp4" and VIDEO.exists():
            return self.respond(VIDEO.read_bytes(), "video/mp4")
        if route == "/attachment":
            return self.respond(IMAGE, "image/png", 'attachment; filename="notch-attachment.png"')
        if route == "/archive":
            return self.respond(PAYLOAD, "application/x-notch-fixture", filename="notch-archive.bin")
        if route == "/protected":
            if "transfer_auth=1" not in self.headers.get("Cookie", ""):
                return self.respond(b"Authentication required", "text/plain", status=403)
            return self.respond(PAYLOAD, "text/plain", 'attachment; filename="notch-protected.txt"')
        if route == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/protected")
            self.end_headers()
            return
        if route in ("/slow", "/failure"):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(2 * 1024 * 1024))
            self.end_headers()
            try:
                for index in range(256):
                    self.wfile.write(b"t" * 8192)
                    self.wfile.flush()
                    if route == "/failure":
                        self.close_connection = True
                        return
                    time.sleep(0.025)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self.respond(b"Missing fixture", "text/plain", status=404)

    def respond(self, body, mime, disposition=None, filename=None, status=200):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        if disposition:
            self.send_header("Content-Disposition", disposition)
        elif filename:
            self.send_header("Content-Disposition", 'inline; filename="' + filename + '"')
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8769)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Transfer fixtures ready at http://127.0.0.1:{server.server_port}", flush=True)
    server.serve_forever()

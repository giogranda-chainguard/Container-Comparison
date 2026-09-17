#!/usr/bin/env python3
import json, os, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT=int(os.environ.get("SCANNER_PORT","9090"))
ALLOWED={
    "upstream": {
        "label": os.environ.get("UPSTREAM_IMAGE","nginx:latest"),
        "target": os.environ.get("UPSTREAM_ID","")
    },
    "chainguard": {
        "label": os.environ.get("CHAINGUARD_IMAGE","cgr.dev/chainguard/nginx:latest"),
        "target": os.environ.get("CHAINGUARD_ID","")
    }
}

def summarize(report):
    counts={"UNKNOWN":0,"LOW":0,"MEDIUM":0,"HIGH":0,"CRITICAL":0}
    for result in report.get("Results") or []:
        for vuln in result.get("Vulnerabilities") or []:
            sev=(vuln.get("Severity") or "UNKNOWN").upper()
            counts[sev]=counts.get(sev,0)+1
    counts["TOTAL"]=sum(v for k,v in counts.items() if k!="TOTAL")
    return counts

class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, payload):
        body=json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Cache-Control","no-store")
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Access-Control-Allow-Methods","GET,OPTIONS")
        self.end_headers()

    def do_GET(self):
        path=urlparse(self.path).path
        if path=="/health":
            return self.send_json(200,{"ok":True})
        if path.startswith("/scan/"):
            key=path.rsplit("/",1)[-1]
            cfg=ALLOWED.get(key)
            if not cfg or not cfg["target"]:
                return self.send_json(404,{"error":"Unknown demo image"})
            try:
                p=subprocess.run(
                    ["trivy","image","--quiet","--format","json",
                     "--scanners","vuln",cfg["target"]],
                    capture_output=True,text=True,timeout=300
                )
                if p.returncode != 0:
                    return self.send_json(500,{"error":p.stderr.strip() or "Trivy failed"})
                report=json.loads(p.stdout)
                return self.send_json(200,{
                    "image":cfg["label"],
                    "image_id":cfg["target"],
                    "summary":summarize(report)
                })
            except subprocess.TimeoutExpired:
                return self.send_json(504,{"error":"Trivy scan timed out"})
            except Exception as e:
                return self.send_json(500,{"error":str(e)})
        self.send_json(404,{"error":"Not found"})

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt%args), flush=True)

ThreadingHTTPServer(("127.0.0.1",PORT),Handler).serve_forever()

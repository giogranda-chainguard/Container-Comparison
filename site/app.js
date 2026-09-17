const scanner = "http://127.0.0.1:9090";

function humanSize(bytes) {
  const units=["B","KB","MB","GB"]; let n=Number(bytes), i=0;
  while(n>=1024 && i<units.length-1){n/=1024;i++}
  return `${n.toFixed(i ? 1 : 0)} ${units[i]}`;
}
async function loadMeta(kind) {
  const r=await fetch(`/.demo/${kind}.json`).catch(()=>null);
  if (!r || !r.ok) return;
  const m=await r.json();
  for (const [k,v] of Object.entries(m)) {
    const el=document.querySelector(`[data-meta="${k}"]`);
    if(el) el.textContent = k==="size" ? humanSize(v) : (v || "(not set)");
  }
}
async function scan(kind) {
  const btn=document.getElementById("scan");
  const status=document.getElementById("status");
  btn.disabled=true; status.textContent="Scanning with Trivy…";
  try {
    const r=await fetch(`${scanner}/scan/${kind}`);
    const d=await r.json();
    if(!r.ok) throw new Error(d.error || "Scan failed");
    for(const sev of ["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","UNKNOWN"]) {
      const el=document.getElementById(sev.toLowerCase());
      if(el) el.textContent=d.summary[sev] ?? 0;
    }
    status.textContent="Scan complete";
  } catch(e) {
    status.textContent=`Scan failed: ${e.message}`;
  } finally { btn.disabled=false; }
}

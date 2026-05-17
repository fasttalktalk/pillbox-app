// Cloudflare Worker — PillBox backend
//
// Secrets (set via: wrangler secret put <NAME>):
//   LINE_TOKEN          — LINE Channel Access Token
//   LINE_USER           — LINE Target User ID
//   FIREBASE_SECRET     — Firebase Realtime Database legacy secret
//   GS_SECRET           — shared secret with Google Apps Script
//
// Environment variable (set in wrangler.toml [vars]):
//   GOOGLE_SCRIPT_URL   — deployed Google Apps Script URL
//   FIREBASE_DB_BASE    — Firebase Realtime Database base URL

const MISSED_THRESHOLD = 10 * 60 * 1000; // 10 นาที

// ─── Helpers ─────────────────────────────────────────────────────────────────

function fbUrl(env, device) {
  return `${env.FIREBASE_DB_BASE}/devices/${encodeURIComponent(device)}.json?auth=${env.FIREBASE_SECRET}`;
}

async function getFirebase(env, device) {
  const res = await fetch(fbUrl(env, device));
  return res.json().catch(() => ({}));
}

async function patchFirebase(env, device, body) {
  const res = await fetch(fbUrl(env, device), {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, status: res.status };
}

async function logToSheet(env, device, note) {
  const res = await fetch(env.GOOGLE_SCRIPT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: env.GS_SECRET, device, note }),
  });
  return { ok: res.ok, status: res.status };
}

async function sendLine(env, message) {
  await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.LINE_TOKEN}`,
    },
    body: JSON.stringify({
      to: env.LINE_USER,
      messages: [{ type: "text", text: message }],
    }),
  });
}

function jsonResp(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function htmlClose(msg) {
  return new Response(
    `<!DOCTYPE html><html lang="th"><head><meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      body{font-family:-apple-system,sans-serif;display:flex;align-items:center;
           justify-content:center;min-height:100vh;margin:0;background:#f0fdf4}
      .box{text-align:center}
      .icon{font-size:60px}
      .msg{font-size:20px;font-weight:700;color:#16A34A;margin-top:12px}
    </style></head>
    <body><div class="box">
      <div class="icon">✅</div>
      <div class="msg">${msg}</div>
    </div>
    <script>setTimeout(function(){ window.close(); }, 1200);</script>
    </body></html>`,
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}

// ─── Missed-dose check (runs on cron schedule) ───────────────────────────────

async function checkMissedDose(env) {
  const device = "pillBox1";
  const data = await getFirebase(env, device);

  if (!data?.alarmActive) return;
  if (data?.lastAckAt) return;

  const now = Date.now();
  const lastAlarmAt = data?.lastAlarmAt || 0;

  if (now - lastAlarmAt < MISSED_THRESHOLD) return;

  await patchFirebase(env, device, { alarmActive: false, lastAckAt: -1 });
  await logToSheet(env, device, "ไม่ได้กินยา ❌");
  await sendLine(env, "⚠️  ไม่ได้กินยาตามเวลา!\nกรุณาตรวจสอบผู้ป่วย");
}

// ─── Main export ──────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const device = url.searchParams.get("device") || "pillBox1";

    // GET /alarm — triggered when it's time to take medicine
    if (url.pathname === "/alarm") {
      const now  = Date.now();
      const time = url.searchParams.get("time") || "";
      const type = url.searchParams.get("type") || "auto";

      const fb = await patchFirebase(env, device, {
        alarmActive: true,
        lastAlarmAt: now,
        lastAckAt: 0,
      });

      const label = type === "manual" ? "manual" : "auto";
      const sheet = await logToSheet(
        env,
        device,
        `ถึงเวลากินยา${time ? " " + time : ""} (${label})`
      );

      return jsonResp({ route: "alarm", device, time, type, firebase: fb, sheet });
    }

    // GET /ack — triggered by LINE button
    if (url.pathname === "/ack") {
      const now       = Date.now();
      const before    = await getFirebase(env, device);
      const lastAckAt = before?.lastAckAt || 0;

      await patchFirebase(env, device, {
        alarmActive: false,
        ackTrigger: now,
        ...(lastAckAt ? {} : { lastAckAt: now }),
      });

      if (lastAckAt) {
        return htmlClose("ยืนยันแล้ว!");
      }

      await logToSheet(env, device, "กินยาแล้ว ✅");
      return htmlClose("ยืนยันแล้ว!");
    }

    return new Response("OK (use /alarm or /ack)", { status: 200 });
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(checkMissedDose(env));
  },
};

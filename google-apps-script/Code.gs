// Google Apps Script — PillBox log to Google Sheets
//
// วิธีใช้:
//   1. เปิด script.google.com สร้าง project ใหม่
//   2. วางโค้ดนี้ใน Code.gs
//   3. เปลี่ยน SECRET ให้ตรงกับ GS_SECRET ใน Cloudflare Worker
//   4. Deploy → New deployment → Web app → Execute as: Me, Who can access: Anyone
//   5. Copy URL ไปใส่ใน GOOGLE_SCRIPT_URL ของ wrangler.toml

const SHEET_NAME = 'pill_log';
const SECRET     = 'YOUR_GS_SECRET';   // ต้องตรงกับ GS_SECRET ใน Cloudflare Worker

function doGet(e) {
  return ContentService
    .createTextOutput('pill_log logger running ✅')
    .setMimeType(ContentService.MimeType.TEXT);
}

// POST JSON: { secret, device, note }
function doPost(e) {
  try {
    const data = JSON.parse(e.postData?.contents || '{}');

    if (data.secret !== SECRET) {
      return ContentService.createTextOutput('bad secret').setMimeType(ContentService.MimeType.TEXT);
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sh = ss.getSheetByName(SHEET_NAME);
    if (!sh) sh = ss.insertSheet(SHEET_NAME);

    if (sh.getLastRow() === 0) {
      sh.appendRow(['server_ts', 'device', 'note']);
    }

    const ts     = new Date();
    const device = data.device || '';
    const note   = data.note   || '';

    sh.appendRow([ts, device, note]);

    return ContentService.createTextOutput('ok').setMimeType(ContentService.MimeType.TEXT);
  } catch (err) {
    return ContentService.createTextOutput('error: ' + err).setMimeType(ContentService.MimeType.TEXT);
  }
}

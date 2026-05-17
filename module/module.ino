#include <WiFi.h>
#include <Wire.h>
#include <RTClib.h>
#include <Preferences.h>

#include <WiFiClientSecure.h>
#include <HTTPClient.h>

#include <Firebase_ESP_Client.h>
#include <time.h>

#include "secrets.h"  // copy secrets.h.example → secrets.h แล้วใส่ค่าของตัวเอง

// ================= Firebase =================
#define DATABASE_URL  "https://pill-box-esp32-default-rtdb.asia-southeast1.firebasedatabase.app/"
const char *deviceId = "pillBox1";

#define WORKER_ACK_URL   "https://pill-box.fasttalktalk.workers.dev/ack?device=pillBox1"
#define WORKER_ALARM_URL "https://pill-box.fasttalktalk.workers.dev/alarm?device=pillBox1"

// ================= Pins =================
const int buzzerPin = 14;
const int ledPin    = 25;

// ================= MAX ALARMS =================
// ✅ แก้: ใช้ MAX_ALARMS แทน hardcode 3
#define MAX_ALARMS 5

// ================= Alarm Struct =================
struct Alarm {
  int hour;
  int minute;
  bool enabled;
  uint8_t daysMask;
  String medicine;
  int pills;
  String note;
};

// ✅ แก้: จาก alarms[3] → alarms[MAX_ALARMS]
Alarm alarms[MAX_ALARMS];

// ================= Firebase Objects =================
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// ================= RTC =================
RTC_DS3231 rtc;

// ✅ แก้: จาก lastAlarmToken[3] → lastAlarmToken[MAX_ALARMS]
long lastAlarmToken[MAX_ALARMS];

long long lastManualTrigger = 0;
long long lastAckTrigger    = 0;

// ================= Preferences =================
Preferences prefs;

bool wifiOK          = false;
bool firebaseStarted = false;

unsigned long lastRtcPrintMs = 0;

// ================= Alert =================
bool alerting              = false;
unsigned long lastBlinkMs  = 0;
unsigned long alertStartMs = 0;
unsigned long alertDurationMs = 5UL * 60UL * 1000UL; // default 5 นาที
bool blinkState            = false;
const unsigned long BLINK_DELAY_MS   = 300;
const unsigned long ALERT_TIMEOUT_MS = 5UL * 60UL * 1000UL;

String alertTimeText = "";
int    alertAlarmIdx = -1; // index alarm ที่กำลัง alert (-1 = manual)
unsigned long lastLineSentMs = 0;
const unsigned long LINE_RESEND_MS = 2UL * 60UL * 1000UL; // resend LINE ทุก 2 นาที

// ------------------------------------------------------
String jsonEscape(const String &s) {
  String out;
  out.reserve(s.length() + 16);
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"':  out += "\\\""; break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:   out += c;      break;
    }
  }
  return out;
}

String hhmm(int h, int m) {
  char buf[6];
  sprintf(buf, "%02d:%02d", h, m);
  return String(buf);
}

String rtcToText(const DateTime& t) {
  char buf[20];
  sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d",
          t.year(), t.month(), t.day(),
          t.hour(), t.minute(), t.second());
  return String(buf);
}

// ------------------------------------------------------
// หา "รอบถัดไป"
// ✅ แก้: loop MAX_ALARMS
String getNextAlarmText(const DateTime& now) {
  bool anySet = false;
  for (int i = 0; i < MAX_ALARMS; i++) {
    if (alarms[i].enabled && (alarms[i].hour != 0 || alarms[i].minute != 0)) {
      anySet = true;
      break;
    }
  }
  if (!anySet) return "ยังไม่ได้ set เวลา";

  long bestDeltaMin = 9999999;
  int bestHour = -1, bestMin = -1;
  int bestIdx  = -1;

  int nowMinOfDay = now.hour() * 60 + now.minute();

  for (int dayOffset = 0; dayOffset <= 7; dayOffset++) {
    DateTime d  = now + TimeSpan(dayOffset, 0, 0, 0);
    int dow     = d.dayOfTheWeek();

    // ✅ แก้: loop MAX_ALARMS
    for (int i = 0; i < MAX_ALARMS; i++) {
      if (!alarms[i].enabled) continue;
      if (alarms[i].hour == 0 && alarms[i].minute == 0) continue;

      bool todayEnabled = (alarms[i].daysMask & (1 << dow)) != 0;
      if (!todayEnabled) continue;

      int alarmMinOfDay = alarms[i].hour * 60 + alarms[i].minute;
      if (dayOffset == 0 && alarmMinOfDay <= nowMinOfDay) continue;

      long deltaMin = dayOffset * 1440L + (alarmMinOfDay - nowMinOfDay);
      if (deltaMin < bestDeltaMin) {
        bestDeltaMin = deltaMin;
        bestHour     = alarms[i].hour;
        bestMin      = alarms[i].minute;
        bestIdx      = i;
      }
    }
  }

  if (bestIdx < 0) return "ยังไม่ได้ตั้งวันเตือน";
  return String("a") + String(bestIdx + 1) + " " + hhmm(bestHour, bestMin);
}

// ------------------------------------------------------
// LINE Flex Message  (alarmIdx = -1 สำหรับ manual trigger)
bool sendLineFlexAck(const String& timeText, int alarmIdx = -1) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("LINE: WiFi not connected -> skip");
    return false;
  }

  // "a3 17:49" → "17:49 น."  /  ข้อความอื่น → แสดงตรงๆ
  String nextRaw = getNextAlarmText(rtc.now());
  String nextDisplay;
  if (nextRaw.length() > 3 && nextRaw[0] == 'a' && nextRaw[2] == ' ') {
    nextDisplay = nextRaw.substring(3) + " น.";
  } else {
    nextDisplay = nextRaw;
  }

  // ── รายละเอียดยา ──
  bool hasDetails = (alarmIdx >= 0 && alarmIdx < MAX_ALARMS &&
                     alarms[alarmIdx].medicine != "ยังไม่ได้ตั้ง" &&
                     alarms[alarmIdx].medicine.length() > 0);
  String medicine = hasDetails ? alarms[alarmIdx].medicine : "";
  int    pills    = hasDetails ? alarms[alarmIdx].pills    : 1;
  String note     = hasDetails ? alarms[alarmIdx].note     : "";

  // สร้างแถว medicine detail ใน JSON
  String medicineRows = "";
  if (hasDetails) {
    medicineRows +=
      // เส้นคั่น + ชื่อยา
      String("{\"type\":\"separator\",\"margin\":\"lg\"},"
      "{"
        "\"type\":\"box\","
        "\"layout\":\"horizontal\","
        "\"margin\":\"md\","
        "\"contents\":["
          "{\"type\":\"text\",\"text\":\"💊 ชื่อยา\",\"size\":\"sm\",\"color\":\"#AAAAAA\",\"flex\":1},"
          "{"
            "\"type\":\"text\","
            "\"text\":\"") + jsonEscape(medicine) + String("\","
            "\"size\":\"sm\","
            "\"color\":\"#111111\","
            "\"weight\":\"bold\","
            "\"align\":\"end\","
            "\"wrap\":true,"
            "\"flex\":2"
          "}"
        "]"
      "},"

      // จำนวน
      "{"
        "\"type\":\"box\","
        "\"layout\":\"horizontal\","
        "\"margin\":\"sm\","
        "\"contents\":["
          "{\"type\":\"text\",\"text\":\"จำนวน\",\"size\":\"sm\",\"color\":\"#AAAAAA\",\"flex\":1},"
          "{"
            "\"type\":\"text\","
            "\"text\":\"") + String(pills) + String(" เม็ด\","
            "\"size\":\"sm\","
            "\"color\":\"#111111\","
            "\"align\":\"end\""
          "}"
        "]"
      "}");

    if (note.length() > 0) {
      medicineRows +=
        // หมายเหตุ
        String(",{"
          "\"type\":\"box\","
          "\"layout\":\"horizontal\","
          "\"margin\":\"sm\","
          "\"contents\":["
            "{\"type\":\"text\",\"text\":\"หมายเหตุ\",\"size\":\"sm\",\"color\":\"#AAAAAA\",\"flex\":1},"
            "{"
              "\"type\":\"text\","
              "\"text\":\"") + jsonEscape(note) + String("\","
              "\"size\":\"sm\","
              "\"color\":\"#E67E22\","
              "\"align\":\"end\","
              "\"wrap\":true,"
              "\"flex\":2"
            "}"
          "]"
        "}");
    }

    medicineRows += ",";
  }

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient https;
  if (!https.begin(client, "https://api.line.me/v2/bot/message/push")) {
    Serial.println("LINE: https.begin failed");
    return false;
  }

  https.addHeader("Content-Type", "application/json");
  https.addHeader("Authorization", String("Bearer ") + LINE_CHANNEL_ACCESS_TOKEN);

  String body =
    String("{\"to\":\"") + LINE_TARGET_USER_ID + "\","
    "\"messages\":[{"
      "\"type\":\"flex\","
      "\"altText\":\"💊 ถึงเวลากินยาแล้ว (" + timeText + " น.)\","
      "\"contents\":{"
        "\"type\":\"bubble\","
        "\"size\":\"mega\","

        // ── Header (แถบสีเขียว) ──
        "\"header\":{"
          "\"type\":\"box\","
          "\"layout\":\"vertical\","
          "\"backgroundColor\":\"#16A34A\","
          "\"paddingAll\":\"14px\","
          "\"contents\":[{"
            "\"type\":\"text\","
            "\"text\":\"💊  PillBox\","
            "\"color\":\"#FFFFFF\","
            "\"size\":\"sm\","
            "\"weight\":\"bold\""
          "}]"
        "},"

        // ── Body ──
        "\"body\":{"
          "\"type\":\"box\","
          "\"layout\":\"vertical\","
          "\"spacing\":\"md\","
          "\"paddingAll\":\"20px\","
          "\"contents\":["

            // หัวข้อ
            "{\"type\":\"text\","
            "\"text\":\"ถึงเวลากินยาแล้ว\","
            "\"weight\":\"bold\","
            "\"size\":\"xl\","
            "\"color\":\"#111111\"},"

            // เวลา (ใหญ่)
            "{"
              "\"type\":\"box\","
              "\"layout\":\"horizontal\","
              "\"spacing\":\"sm\","
              "\"contents\":["
                "{\"type\":\"text\",\"text\":\"🕐\",\"size\":\"xl\",\"flex\":0},"
                "{"
                  "\"type\":\"text\","
                  "\"text\":\"" + timeText + " น.\","
                  "\"size\":\"3xl\","
                  "\"weight\":\"bold\","
                  "\"color\":\"#16A34A\","
                  "\"flex\":1"
                "}"
              "]"
            "},"

            // เส้นคั่น
            "{\"type\":\"separator\",\"margin\":\"lg\"},"

            // รายละเอียดยา (medicine, pills, note) ถ้ามี
            + medicineRows +

            // รอบถัดไป
            "{"
              "\"type\":\"box\","
              "\"layout\":\"horizontal\","
              "\"margin\":\"md\","
              "\"contents\":["
                "{\"type\":\"text\",\"text\":\"รอบถัดไป\",\"size\":\"sm\",\"color\":\"#AAAAAA\",\"flex\":1},"
                "{"
                  "\"type\":\"text\","
                  "\"text\":\"" + jsonEscape(nextDisplay) + "\","
                  "\"size\":\"sm\","
                  "\"color\":\"#555555\","
                  "\"align\":\"end\""
                "}"
              "]"
            "}"

          "]"
        "},"

        // ── Footer (ปุ่ม) ──
        "\"footer\":{"
          "\"type\":\"box\","
          "\"layout\":\"vertical\","
          "\"paddingAll\":\"16px\","
          "\"contents\":[{"
            "\"type\":\"button\","
            "\"style\":\"primary\","
            "\"color\":\"#16A34A\","
            "\"action\":{"
              "\"type\":\"uri\","
              "\"label\":\"✅  ยืนยันกินยาแล้ว\","
              "\"uri\":\"" + String(WORKER_ACK_URL) + "\""
            "}"
          "}]"
        "}"

      "}"
    "}]}";

  int code = https.POST(body);
  String resp = https.getString();
  https.end();

  Serial.printf("LINE FLEX: HTTP %d\n", code);
  if (code != 200) Serial.println(resp);
  return (code == 200);
}

// ------------------------------------------------------
// Worker /alarm
bool notifyWorkerAlarm(const String& timeText, const String& type) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WORKER: no wifi -> skip /alarm");
    return false;
  }

  String u = String(WORKER_ALARM_URL) + "&time=" + timeText + "&type=" + type;

  HTTPClient http;
  if (!http.begin(u)) {
    Serial.println("WORKER: http.begin failed");
    return false;
  }

  int code = http.GET();
  String resp = http.getString();
  http.end();

  Serial.printf("WORKER /alarm: HTTP %d\n", code);
  if (code != 200) Serial.println(resp);
  return (code == 200);
}

// ------------------------------------------------------
// ✅ เพิ่มใหม่: เขียนประวัติการกินยาลง Firebase
void writeHistory(int alarmIndex, const String& timeText, const String& type) {
  if (!firebaseStarted || !Firebase.ready()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  String histPath = String("devices/") + deviceId + "/history/" +
                    (alarmIndex < 0 ? "manual" : "a" + String(alarmIndex + 1));

  FirebaseJson entry;
  entry.set("takenAt/.sv", "timestamp"); // server timestamp
  entry.set("alarmTime", timeText);
  entry.set("type", type);              // "auto" หรือ "manual"

  if (Firebase.RTDB.pushJSON(&fbdo, histPath.c_str(), &entry)) {
    Serial.printf("[History] Written a%d type=%s\n", alarmIndex + 1, type.c_str());
  } else {
    Serial.printf("[History] Failed: %s\n", fbdo.errorReason().c_str());
  }
}

// ------------------------------------------------------
// buzzer + led
void hwOff() {
  digitalWrite(buzzerPin, HIGH);
  digitalWrite(ledPin, LOW);
}

void startAlert(const String& reason, unsigned long durationMs = ALERT_TIMEOUT_MS) {
  if (alerting) {
    Serial.println("ALERT already running (skip start)");
    return;
  }
  alerting       = true;
  alertStartMs   = millis();
  alertDurationMs = durationMs;
  lastBlinkMs    = 0;
  blinkState     = false;
  Serial.printf("ALERT START reason: %s duration: %lus\n", reason.c_str(), durationMs / 1000);
}

void stopAlert(const String& reason) {
  if (!alerting) {
    Serial.println("ALERT not running (skip stop)");
    return;
  }
  alerting = false;
  alertTimeText = "";
  hwOff();
  Serial.print("ALERT STOP reason: ");
  Serial.println(reason);
}

void updateAlert() {
  if (!alerting) return;
  if (millis() - alertStartMs >= alertDurationMs) {
    stopAlert("timeout");
    return;
  }
  if (millis() - lastBlinkMs >= BLINK_DELAY_MS) {
    lastBlinkMs = millis();
    blinkState  = !blinkState;
    digitalWrite(buzzerPin, blinkState ? LOW  : HIGH);
    digitalWrite(ledPin,    blinkState ? HIGH : LOW);
  }
}

// ------------------------------------------------------
// Flash Cache
void loadCacheFromFlash() {
  prefs.begin("pillbox", true);

  // ✅ แก้: loop MAX_ALARMS
  for (int i = 0; i < MAX_ALARMS; i++) {
    String p           = "a" + String(i + 1) + "_";
    alarms[i].hour     = prefs.getInt((p + "h").c_str(), 0);
    alarms[i].minute   = prefs.getInt((p + "m").c_str(), 0);
    alarms[i].enabled  = prefs.getBool((p + "en").c_str(), false);
    alarms[i].daysMask = (uint8_t)prefs.getUChar((p + "dy").c_str(), 0x7F);
    alarms[i].medicine = prefs.getString((p + "med").c_str(), "ยังไม่ได้ตั้ง");
    alarms[i].pills    = prefs.getInt((p + "pills").c_str(), 1);
    alarms[i].note     = prefs.getString((p + "note").c_str(), "");
    lastAlarmToken[i]  = -1; // ✅ init ทุก slot
  }

  prefs.end();

  Serial.println("=== Loaded cache from Flash ===");
  for (int i = 0; i < MAX_ALARMS; i++) {
    Serial.printf("Cache Alarm %d: %02d:%02d en=%d daysMask=0x%02X\n",
                  i + 1, alarms[i].hour, alarms[i].minute,
                  alarms[i].enabled, alarms[i].daysMask);
  }
}

void saveCacheToFlash() {
  prefs.begin("pillbox", false);

  // ✅ แก้: loop MAX_ALARMS
  for (int i = 0; i < MAX_ALARMS; i++) {
    String p = "a" + String(i + 1) + "_";
    prefs.putInt((p + "h").c_str(), alarms[i].hour);
    prefs.putInt((p + "m").c_str(), alarms[i].minute);
    prefs.putBool((p + "en").c_str(), alarms[i].enabled);
    prefs.putUChar((p + "dy").c_str(), alarms[i].daysMask);
    prefs.putString((p + "med").c_str(), alarms[i].medicine);
    prefs.putInt((p + "pills").c_str(), alarms[i].pills);
    prefs.putString((p + "note").c_str(), alarms[i].note);
  }

  prefs.end();
  Serial.println("=== Saved cache to Flash ===");
}

// ------------------------------------------------------
// NTP → RTC sync
void syncRTCFromNTP() {
  configTime(7 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("[NTP] Syncing...");
  struct tm timeinfo;
  int retry = 0;
  while (!getLocalTime(&timeinfo) && retry < 20) {
    updateAlert();
    delay(500);
    Serial.print(".");
    retry++;
  }
  Serial.println();
  if (retry >= 20) {
    Serial.println("[NTP] Sync failed — RTC not updated");
    return;
  }
  rtc.adjust(DateTime(
    timeinfo.tm_year + 1900,
    timeinfo.tm_mon  + 1,
    timeinfo.tm_mday,
    timeinfo.tm_hour,
    timeinfo.tm_min,
    timeinfo.tm_sec
  ));
  Serial.printf("[NTP] RTC set: %04d-%02d-%02d %02d:%02d:%02d\n",
    timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
    timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
}

// ------------------------------------------------------
// WiFi connect
bool connectWiFiNonBlocking(unsigned long timeoutMs = 20000) {
  Serial.printf("Connecting WiFi: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start   = millis();
  unsigned long lastDot = 0;
  while (WiFi.status() != WL_CONNECTED && millis() - start < timeoutMs) {
    updateAlert();
    if (millis() - lastDot >= 300) {
      lastDot = millis();
      Serial.print(".");
    }
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
    return true;
  } else {
    Serial.println("WiFi NOT connected (offline mode).");
    return false;
  }
}

// ------------------------------------------------------
// Firebase init
void initFirebase() {
  config.api_key      = API_KEY;
  config.database_url = DATABASE_URL;

  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("Firebase signUp OK");
  } else {
    Serial.printf("Firebase signUp failed: %s\n",
                  config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectNetwork(true);
  firebaseStarted = true;

  Serial.println("Firebase begin() called.");
}

// ------------------------------------------------------
// Sync settings Firebase -> RAM -> Flash
// ✅ แก้: loop MAX_ALARMS
bool syncSettingsFromFirebase() {
  String base   = "devices/" + String(deviceId);
  bool changed  = false;

  for (int i = 0; i < MAX_ALARMS; i++) {
    String path = base + "/alarms/a" + String(i + 1);

    if (Firebase.RTDB.getJSON(&fbdo, path)) {
      FirebaseJson *json = fbdo.to<FirebaseJson *>();
      FirebaseJsonData r;

      int    h    = alarms[i].hour;
      int    m    = alarms[i].minute;
      bool   en   = alarms[i].enabled;
      int    days = alarms[i].daysMask;
      String med  = alarms[i].medicine;
      int    pils = alarms[i].pills;
      String nt   = alarms[i].note;

      json->get(r, "hour");     if (r.success) h    = r.to<int>();
      json->get(r, "minute");   if (r.success) m    = r.to<int>();
      json->get(r, "enabled");  en   = r.success ? r.to<bool>()   : true;
      json->get(r, "days");     days = r.success ? r.to<int>()    : 0x7F;
      json->get(r, "medicine"); if (r.success) med  = r.to<String>();
      json->get(r, "pills");    if (r.success) pils = r.to<int>();
      json->get(r, "note");     if (r.success) nt   = r.to<String>();

      if (alarms[i].hour != h || alarms[i].minute != m ||
          alarms[i].enabled != en || alarms[i].daysMask != (uint8_t)days ||
          alarms[i].medicine != med || alarms[i].pills != pils || alarms[i].note != nt) {
        alarms[i].hour     = h;
        alarms[i].minute   = m;
        alarms[i].enabled  = en;
        alarms[i].daysMask = (uint8_t)days;
        alarms[i].medicine = med;
        alarms[i].pills    = pils;
        alarms[i].note     = nt;
        changed            = true;
      }

      Serial.printf("Alarm %d: %02d:%02d en=%d daysMask=0x%02X\n",
                    i + 1, alarms[i].hour, alarms[i].minute,
                    alarms[i].enabled, alarms[i].daysMask);
    } else {
      // path ไม่มีใน Firebase → ลบออกจาก RAM+Flash
      if (alarms[i].enabled || alarms[i].hour != 0 || alarms[i].minute != 0) {
        alarms[i].hour     = 0;
        alarms[i].minute   = 0;
        alarms[i].enabled  = false;
        alarms[i].daysMask = 0x7F;
        alarms[i].medicine = "ยังไม่ได้ตั้ง";
        alarms[i].pills    = 1;
        alarms[i].note     = "";
        changed = true;
        Serial.printf("Alarm %d: cleared (not in Firebase)\n", i + 1);
      }
    }
  }

  if (changed) saveCacheToFlash();
  return changed;
}

// ------------------------------------------------------
// Manual trigger
void checkManualTrigger() {
  String base = "devices/" + String(deviceId);

  if (Firebase.RTDB.get(&fbdo, base + "/manualTrigger")) {
    long long ts = fbdo.to<long long>();
    if (ts != 0 && ts != lastManualTrigger) {
      lastManualTrigger = ts;

      DateTime nowRtc = rtc.now();
      Serial.printf("[MANUAL] trigger | RTC=%s\n", rtcToText(nowRtc).c_str());

      String timeText = hhmm(nowRtc.hour(), nowRtc.minute());

      unsigned long duration = ALERT_TIMEOUT_MS;
      if (Firebase.RTDB.getInt(&fbdo, base + "/manualDuration")) {
        int sec = fbdo.to<int>();
        if (sec > 0) duration = (unsigned long)sec * 1000UL;
      }

      sendLineFlexAck(timeText, -1);
      notifyWorkerAlarm(timeText, "manual");
      writeHistory(-1, timeText, "manual");

      alertTimeText  = timeText;
      alertAlarmIdx  = -1;
      lastLineSentMs = millis();
      startAlert("manualTrigger", duration);
    }
  }
}

// ------------------------------------------------------
// ACK trigger
void checkAckTrigger() {
  String base = "devices/" + String(deviceId);

  if (Firebase.RTDB.get(&fbdo, base + "/ackTrigger")) {
    long long ts = fbdo.to<long long>();
    if (ts != 0 && ts != lastAckTrigger) {
      lastAckTrigger = ts;

      DateTime nowRtc = rtc.now();
      Serial.printf("[ACK] trigger -> STOP | RTC=%s\n", rtcToText(nowRtc).c_str());

      stopAlert("ackTrigger");
    }
  }
}

// ------------------------------------------------------
// RTC alarm check
// ✅ แก้: loop MAX_ALARMS + เพิ่ม writeHistory
void checkAlarmsByRTC() {
  DateTime now = rtc.now();

  int curHour   = now.hour();
  int curMinute = now.minute();
  int curDay    = now.day();
  int dow       = now.dayOfTheWeek();

  long token = curDay * 1440L + curHour * 60 + curMinute;

  for (int i = 0; i < MAX_ALARMS; i++) {
    if (!alarms[i].enabled) continue;

    bool todayEnabled = (alarms[i].daysMask & (1 << dow)) != 0;
    if (!todayEnabled) continue;

    if (alarms[i].hour == curHour && alarms[i].minute == curMinute) {
      if (lastAlarmToken[i] != token) {
        lastAlarmToken[i] = token;

        String timeText = hhmm(curHour, curMinute);
        Serial.printf("[AUTO] Alarm %d TRIGGERED | time=%s | RTC=%s\n",
                      i + 1, timeText.c_str(), rtcToText(now).c_str());

        sendLineFlexAck(timeText, i);
        notifyWorkerAlarm(timeText, "auto");
        writeHistory(i, timeText, "auto");

        alertTimeText  = timeText;
        alertAlarmIdx  = i;
        lastLineSentMs = millis();
        startAlert(String("auto alarm ") + String(i + 1) + " at " + timeText);
      }
    }
  }
}

// ================= setup =================
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(buzzerPin, OUTPUT);
  pinMode(ledPin, OUTPUT);
  hwOff();

  Wire.begin();
  if (!rtc.begin()) {
    Serial.println("RTC not found!");
  } else {
    Serial.println("RTC found.");
  }

  loadCacheFromFlash();

  wifiOK = connectWiFiNonBlocking(20000);
  if (wifiOK) {
    syncRTCFromNTP();
    initFirebase();

    // อ่านค่า trigger ปัจจุบันกัน re-trigger หลัง reboot
    String base = "devices/" + String(deviceId);
    if (Firebase.RTDB.get(&fbdo, base + "/manualTrigger"))
      lastManualTrigger = fbdo.to<long long>();
    if (Firebase.RTDB.get(&fbdo, base + "/ackTrigger"))
      lastAckTrigger = fbdo.to<long long>();
    Serial.printf("[Init] manualTrigger=%lld ackTrigger=%lld\n",
                  lastManualTrigger, lastAckTrigger);
  }

  Serial.println("=== READY ===");
}

// ================= loop =================
void loop() {
  static unsigned long lastRTCCheck    = 0;
  static unsigned long lastWiFiRetry   = 0;
  static unsigned long lastFbSync      = 0;
  static unsigned long lastAckPoll     = 0;
  // ✅ เพิ่มใหม่: heartbeat lastSeen
  static unsigned long lastHeartbeat   = 0;

  unsigned long nowMs = millis();

  // 0) blink/buzzer non-blocking
  updateAlert();

  // 0.2) Resend LINE ทุก 2 นาที ถ้ายัง alerting + WiFi อยู่
  if (alerting && wifiOK && alertTimeText.length() > 0 &&
      nowMs - lastLineSentMs >= LINE_RESEND_MS) {
    lastLineSentMs = nowMs;
    Serial.println("[RESEND] Sending LINE again...");
    sendLineFlexAck(alertTimeText, alertAlarmIdx);
  }

  // 0.1) Print RTC ทุกวินาที
  if (nowMs - lastRtcPrintMs >= 1000) {
    lastRtcPrintMs = nowMs;
    Serial.print("[RTC] ");
    Serial.println(rtcToText(rtc.now()));
  }

  // 1) เช็ค RTC ทุก 1 วิ
  if (nowMs - lastRTCCheck >= 1000) {
    lastRTCCheck = nowMs;
    checkAlarmsByRTC();
  }

  // 2) WiFi หลุด → retry ทุก 15 วิ
  if (WiFi.status() != WL_CONNECTED) {
    wifiOK = false;
    if (nowMs - lastWiFiRetry > 15000) {
      lastWiFiRetry = nowMs;
      Serial.println("WiFi retry...");
      wifiOK = connectWiFiNonBlocking(8000);
      if (wifiOK && !firebaseStarted) initFirebase();
    }
  } else {
    wifiOK = true;
  }

  // 3) Firebase ยังไม่พร้อม → ข้าม
  if (!firebaseStarted || !Firebase.ready()) return;

  // 4) Poll ACK ทุก 300ms
  if (nowMs - lastAckPoll >= 300) {
    lastAckPoll = nowMs;
    checkAckTrigger();
  }

  // 5) Sync + manualTrigger ทุก 5 วิ
  if (nowMs - lastFbSync > 5000) {
    lastFbSync = nowMs;
    syncSettingsFromFirebase();
    checkManualTrigger();
  }

  // 6) ✅ เพิ่มใหม่: Heartbeat lastSeen ทุก 60 วิ
  if (nowMs - lastHeartbeat >= 60000) {
    lastHeartbeat = nowMs;
    String path = String("devices/") + deviceId + "/lastSeen";
    if (Firebase.RTDB.setTimestamp(&fbdo, path.c_str())) {
      Serial.println("[Heartbeat] lastSeen updated");
    } else {
      Serial.printf("[Heartbeat] failed: %s\n", fbdo.errorReason().c_str());
    }
  }
}

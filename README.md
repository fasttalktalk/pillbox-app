# PillBox

ระบบตู้ยาอัจฉริยะ ประกอบด้วย Flutter app, ESP32 firmware และ Firebase backend  
แจ้งเตือนผ่าน LINE Messaging API เมื่อถึงเวลากินยา

## ภาพรวมระบบ

```
Flutter App (iOS/Android)
    │  อ่าน/เขียนตารางยา
    ▼
Firebase Realtime Database
    │  ซิงก์ตารางยา + รับ trigger
    ▼
ESP32 (PillBox Hardware)
    │  ส่ง LINE เมื่อถึงเวลา
    ▼
LINE Messaging API → ผู้ใช้
```

## ฟีเจอร์

- ตั้งเวลาแจ้งเตือนได้สูงสุด 5 รอบต่อวัน
- เลือกวันในสัปดาห์ที่ต้องการแจ้งเตือน
- บันทึกชื่อยา จำนวนเม็ด และหมายเหตุ
- แจ้งเตือนผ่าน LINE Flex Message พร้อมปุ่มยืนยัน
- ส่ง LINE ซ้ำทุก 2 นาทีจนกว่าจะกด ACK
- บันทึกประวัติการกินยาลง Firebase
- รองรับ role: user / owner / admin

## โครงสร้างโปรเจกต์

```
pillbox-app/
├── lib/                    # Flutter app (Dart)
│   ├── main.dart
│   ├── firebase_options.dart
│   ├── login_page.dart
│   ├── pill_page.dart
│   └── profile_page.dart
├── module/                 # ESP32 firmware (Arduino C++)
│   ├── module.ino
│   ├── secrets.h.example   # template — copy เป็น secrets.h
│   └── secrets.h           # ไม่ commit (gitignored)
├── android/
├── ios/
└── pubspec.yaml
```

## การติดตั้ง

### Flutter App

1. ติดตั้ง [Flutter SDK](https://docs.flutter.dev/get-started/install)
2. Clone repo นี้
3. รัน `flutter pub get`
4. รัน `flutter run`

### ESP32 Firmware

1. ติดตั้ง [Arduino IDE](https://www.arduino.cc/en/software) + ESP32 board package
2. ติดตั้ง libraries:
   - `Firebase ESP Client` (mobizt)
   - `RTClib` (Adafruit)
3. Copy `module/secrets.h.example` → `module/secrets.h`
4. ใส่ค่า WiFi, Firebase API key และ LINE token ใน `secrets.h`
5. Upload ไปยัง ESP32

### Firebase Setup

1. สร้าง project ใน [Firebase Console](https://console.firebase.google.com/)
2. เปิด Realtime Database
3. ตั้ง Security Rules ให้ต้อง authenticated
4. รัน `flutterfire configure` เพื่อสร้าง `firebase_options.dart` ใหม่

### LINE Messaging API

1. สร้าง channel ใน [LINE Developers](https://developers.line.biz/)
2. ออก Channel Access Token
3. ใส่ใน `module/secrets.h`

## Hardware

| ชิ้นส่วน | รายละเอียด |
|---------|-----------|
| MCU | ESP32 |
| RTC | DS3231 |
| Buzzer | Active buzzer — Pin 14 |
| LED | Pin 25 |

## Database Structure (Firebase RTDB)

```
devices/
  pillBox1/
    alarms/
      a1/ { hour, minute, enabled, days, medicine, pills, note }
      ...
      a5/
    manualTrigger: <timestamp>
    ackTrigger:    <timestamp>
    lastSeen:      <timestamp>
    history/
      a1/ { takenAt, alarmTime, type }
      manual/ { ... }
```

## การตั้งค่า secrets.h

```cpp
#define WIFI_SSID      "ชื่อ WiFi"
#define WIFI_PASSWORD  "รหัส WiFi"
#define API_KEY        "Firebase API Key"
#define LINE_CHANNEL_ACCESS_TOKEN "LINE Token"
#define LINE_TARGET_USER_ID       "LINE User ID"
```

> **Note:** Firebase API keys ใน `firebase_options.dart` และไฟล์ `google-services.json` / `GoogleService-Info.plist`  
> เป็น public client config ตามมาตรฐาน Firebase — ความปลอดภัยควบคุมโดย Firebase Security Rules

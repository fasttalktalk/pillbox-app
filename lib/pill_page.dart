import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'profile_page.dart';

// ── Design Tokens ──────────────────────────────────────────
class AppColors {
  static const bg         = Color(0xFF0A0E1A);
  static const surface    = Color(0xFF131929);
  static const card       = Color(0xFF1C2438);
  static const accent     = Color(0xFF4F8EF7);
  static const accentGlow = Color(0x334F8EF7);
  static const success    = Color(0xFF4ECDC4);
  static const successGlow= Color(0x334ECDC4);
  static const warning    = Color(0xFFFFB347);
  static const error      = Color(0xFFFF6B6B);
  static const textPrimary   = Color(0xFFEDF2FF);
  static const textSecondary = Color(0xFF8A9BC0);
  static const divider    = Color(0xFF232D45);
}

class PillPage extends StatefulWidget {
  const PillPage({super.key});
  @override
  State<PillPage> createState() => _PillPageState();
}

class _PillPageState extends State<PillPage> {

  String deviceId   = "";
  late DatabaseReference deviceRef;
  StreamSubscription? _alarmSub;
  StreamSubscription? _statusSub;

  final List<TimeOfDay?> _alarms        = [];
  final List<int>        _daysMask      = [];
  final List<String>     _medicineNames = [];
  final List<int>        _pillCounts    = [];
  final List<bool>       _enabled       = [];
  final List<String>     _notes         = [];

  bool   _loading      = true;
  String _status       = "กำลังโหลด...";
  bool   _deviceOnline = false;
  String _deviceName   = "";
  String role          = "user";
  bool   isAdmin       = false;
  bool   canControl    = false; // owner และ admin ควบคุมได้

  final List<String> _dayLabels = const ["อา","จ","อ","พ","พฤ","ศ","ส"];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    deviceRef = FirebaseDatabase.instance.ref("devices/$deviceId");
    _loadUserRole();
    _loadUserDevice();
  }

  @override
  void dispose() {
    _alarmSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final uid  = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseDatabase.instance.ref("users/$uid/role").get();
    if (snap.exists) {
      role       = snap.value.toString();
      isAdmin    = role == "admin";
      canControl = role == "admin" || role == "owner";
    }
    setState(() {});
  }

  Future<void> _loadUserDevice() async {
    final uid  = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseDatabase.instance.ref("users/$uid").get();
    if (!snap.exists) return;
    final data  = Map<String, dynamic>.from(snap.value as Map);
    deviceId    = data["deviceId"] ?? "";
    _deviceName = deviceId;
    deviceRef   = FirebaseDatabase.instance.ref("devices/$deviceId");
    _listenAlarms();
    _listenDeviceStatus();
    setState(() {});
  }

  void _listenAlarms() {
    if (deviceId.isEmpty) return;
    _alarmSub?.cancel();
    _alarmSub = deviceRef.child("alarms").onValue.listen((event) {
      _alarms.clear(); _daysMask.clear(); _medicineNames.clear();
      _pillCounts.clear(); _enabled.clear(); _notes.clear();

      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final keys = data.keys.toList()..sort();
        for (final k in keys) {
          final m = Map<String, dynamic>.from(data[k]);
          _alarms.add(m["hour"] != null
              ? TimeOfDay(hour: m["hour"], minute: m["minute"]) : null);
          _daysMask.add((m["days"] is int) ? m["days"] : 0x7F);
          _medicineNames.add(m["medicine"]?.toString() ?? "ยังไม่ได้ตั้ง");
          _pillCounts.add((m["pills"] is int) ? m["pills"] : 1);
          _enabled.add(m["enabled"] == true);
          _notes.add(m["note"]?.toString() ?? "");
        }
      }
      if (mounted) setState(() { _loading = false; _status = "อัปเดตแล้ว"; });
    }, onError: (_) {
      // ถูก cancel หลัง logout → ไม่ต้องทำอะไร
      _alarmSub?.cancel();
    });
  }

  void _listenDeviceStatus() {
    if (deviceId.isEmpty) return;
    _statusSub?.cancel();
    _statusSub = deviceRef.child("lastSeen").onValue.listen((event) {
      if (!event.snapshot.exists) { setState(() => _deviceOnline = false); return; }
      final ts   = event.snapshot.value as int? ?? 0;
      final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
      if (mounted) setState(() => _deviceOnline = diff.inMinutes < 2);
    }, onError: (_) {
      // ถูก cancel หลัง logout → ไม่ต้องทำอะไร
      _statusSub?.cancel();
    });
  }

  Future<void> _addAlarm() async {
    final index = _alarms.length;
    await deviceRef.child("alarms/a${index + 1}").set({
      "enabled": false, "days": 0x7F,
      "medicine": "ยังไม่ได้ตั้ง", "pills": 1, "note": "",
    });
    setState(() => _status = "เพิ่มรอบกินยาแล้ว");
  }

  Future<void> _confirmDelete(int index) async {
    final ok = await _showConfirmDialog(
      title: "ลบรอบกินยา",
      content: "ต้องการลบรอบที่ ${index + 1} (${_medicineNames[index]}) ?",
      confirmLabel: "ลบ",
      danger: true,
    );
    if (ok != true) return;

    setState(() => _status = "กำลังลบและจัดเรียงใหม่...");

    // 1. snapshot ค่าปัจจุบันก่อน cancel listener
    final snapAlarms    = List<TimeOfDay?>.from(_alarms);
    final snapDaysMask  = List<int>.from(_daysMask);
    final snapMedicine  = List<String>.from(_medicineNames);
    final snapPills     = List<int>.from(_pillCounts);
    final snapEnabled   = List<bool>.from(_enabled);
    final snapNotes     = List<String>.from(_notes);
    final total         = snapAlarms.length;

    // 2. หยุด listener ชั่วคราว
    _alarmSub?.cancel();

    // 3. ตัด index ที่ลบออกจาก snapshot
    snapAlarms.removeAt(index);
    snapDaysMask.removeAt(index);
    snapMedicine.removeAt(index);
    snapPills.removeAt(index);
    snapEnabled.removeAt(index);
    snapNotes.removeAt(index);

    // 4. ลบ node เดิมทั้งหมดใน Firebase
    for (int i = 1; i <= total; i++) {
      await deviceRef.child("alarms/a$i").remove();
    }

    // 5. เขียนกลับด้วย index ใหม่
    for (int i = 0; i < snapAlarms.length; i++) {
      final t    = snapAlarms[i];
      final data = <String, dynamic>{
        "enabled":  snapEnabled[i],
        "days":     snapDaysMask[i],
        "medicine": snapMedicine[i],
        "pills":    snapPills[i],
        "note":     snapNotes[i],
      };
      if (t != null) { data["hour"] = t.hour; data["minute"] = t.minute; }
      await deviceRef.child("alarms/a${i + 1}").set(data);
    }

    // 6. เปิด listener ใหม่
    _listenAlarms();
    setState(() => _status = "ลบและจัดเรียงใหม่แล้ว");
  }

  Future<void> _editMedicine(int index) async {
    final nameCtrl  = TextEditingController(text: _medicineNames[index]);
    final pillsCtrl = TextEditingController(text: _pillCounts[index].toString());
    final noteCtrl  = TextEditingController(text: _notes[index]);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DarkDialog(
        title: "ตั้งค่ายา",
        confirmLabel: "บันทึก",
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _DarkField(controller: nameCtrl, label: "ชื่อยา", icon: Icons.medication_outlined),
          const SizedBox(height: 12),
          _DarkField(controller: pillsCtrl, label: "จำนวนเม็ด",
              icon: Icons.tag, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _DarkField(controller: noteCtrl, label: "หมายเหตุ",
              icon: Icons.sticky_note_2_outlined),
        ]),
      ),
    );
    if (ok == true) {
      await deviceRef.child("alarms/a${index + 1}").update({
        "medicine": nameCtrl.text,
        "pills": int.tryParse(pillsCtrl.text) ?? 1,
        "note": noteCtrl.text,
      });
    }
  }

  Future<void> _toggleEnabled(int index, bool value) async {
    await deviceRef.child("alarms/a${index + 1}").update({"enabled": value});
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _alarms[index] ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.accent, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      await deviceRef.child("alarms/a${index + 1}").update({
        "hour": picked.hour, "minute": picked.minute,
        "enabled": true, "days": _daysMask[index],
      });
    }
  }

  void _toggleDay(int alarm, int day) {
    deviceRef.child("alarms/a${alarm + 1}/days")
        .set(_daysMask[alarm] ^ (1 << day));
  }

  Future<void> _showManualHistory() async {
    final snap = await deviceRef.child("history/manual").get();
    List<Map> records = [];
    if (snap.exists && snap.value is Map) {
      final raw = Map<String, dynamic>.from(snap.value as Map);
      records = raw.values.map((v) => Map<String, dynamic>.from(v)).toList();
      records.sort((a, b) =>
          (b["takenAt"] as int? ?? 0).compareTo(a["takenAt"] as int? ?? 0));
    }
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.campaign_outlined, color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text("ประวัติ Manual Trigger",
                  style: TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 320,
              child: records.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inbox_outlined,
                          color: AppColors.textSecondary, size: 48),
                      const SizedBox(height: 12),
                      const Text("ยังไม่มีประวัติ",
                          style: TextStyle(color: AppColors.textSecondary)),
                    ]))
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (_, i) {
                        final r  = records[i];
                        final ts = r["takenAt"] as int? ?? 0;
                        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.campaign_outlined,
                                color: AppColors.warning, size: 18),
                          ),
                          title: Text(
                            "${dt.day}/${dt.month}/${dt.year}  "
                            "${dt.hour.toString().padLeft(2,'0')}:"
                            "${dt.minute.toString().padLeft(2,'0')}",
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 14)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                  backgroundColor: AppColors.divider,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text("ปิด",
                  style: TextStyle(color: AppColors.textSecondary)),
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _sendManualTest() async {
    await deviceRef.child("manualTrigger").set(ServerValue.timestamp);
    await deviceRef.child("manualDuration").set(10);
    setState(() => _status = "ส่ง Manual Trigger แล้ว");
  }

  Future<void> _showHistory(int index) async {
    final snap = await deviceRef.child("history/a${index + 1}").get();
    List<Map> records = [];
    if (snap.exists && snap.value is Map) {
      final raw = Map<String, dynamic>.from(snap.value as Map);
      records   = raw.values.map((v) => Map<String, dynamic>.from(v)).toList();
      records.sort((a, b) =>
          (b["takenAt"] as int? ?? 0).compareTo(a["takenAt"] as int? ?? 0));
    }
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.history, color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text("ประวัติรอบ ${index + 1} · ${_medicineNames[index]}",
                  style: const TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 320,
              child: records.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inbox_outlined,
                          color: AppColors.textSecondary, size: 48),
                      const SizedBox(height: 12),
                      const Text("ยังไม่มีประวัติการกินยา",
                          style: TextStyle(color: AppColors.textSecondary)),
                    ]))
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (_, i) {
                        final r  = records[i];
                        final ts = r["takenAt"] as int? ?? 0;
                        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                        final note = r["note"]?.toString() ?? "";
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.successGlow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check,
                                color: AppColors.success, size: 18),
                          ),
                          title: Text(
                            "${dt.day}/${dt.month}/${dt.year}  "
                            "${dt.hour.toString().padLeft(2,'0')}:"
                            "${dt.minute.toString().padLeft(2,'0')}",
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 14)),
                          subtitle: note.isNotEmpty
                              ? Text(note, style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12))
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                  backgroundColor: AppColors.divider,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text("ปิด",
                  style: TextStyle(color: AppColors.textSecondary)),
            )),
          ]),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title, required String content,
    required String confirmLabel, bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.divider))),
                child: const Text("ยกเลิก",
                    style: TextStyle(color: AppColors.textSecondary)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: danger ? AppColors.error : AppColors.accent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text(confirmLabel,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  String _timeText(TimeOfDay? t) => t == null
      ? "-- : --"
      : "${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}";

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_deviceName.isEmpty ? "PillBox" : _deviceName,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w600)),
            Row(children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: _deviceOnline ? AppColors.success : AppColors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _deviceOnline ? "ออนไลน์" : "ออฟไลน์",
                style: TextStyle(
                    fontSize: 11,
                    color: _deviceOnline
                        ? AppColors.success
                        : AppColors.textSecondary),
              ),
            ]),
          ],
        ),
        actions: [
          if (deviceId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _showManualHistory,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(Icons.campaign_outlined,
                      color: AppColors.warning, size: 20),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()));
              },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Icon(Icons.person_outline,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
          ),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.card,
              onRefresh: () async { _listenAlarms(); _listenDeviceStatus(); },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [

                  // ── STATUS BAR ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 8, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(_status, style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // ── ALARM LIST ──
                  Expanded(
                    child: _alarms.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(Icons.medication_outlined,
                                  color: AppColors.textSecondary, size: 40),
                            ),
                            const SizedBox(height: 16),
                            const Text("ยังไม่มีรอบกินยา",
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 17, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            if (canControl)
                              const Text("กด + เพื่อเพิ่มรอบกินยา",
                                  style: TextStyle(
                                      color: AppColors.textSecondary, fontSize: 13)),
                          ]))
                        : ListView.builder(
                            itemCount: _alarms.length,
                            itemBuilder: (_, i) => _buildAlarmCard(i),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // ── BOTTOM BUTTONS ──
                  Row(children: [
                    Expanded(child: _ActionButton(
                      label: "เพิ่มรอบกินยา",
                      icon: Icons.add,
                      color: AppColors.accent,
                      onPressed: canControl && _alarms.length < 5 ? _addAlarm : null,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(
                      label: "แจ้งเตือน",
                      icon: Icons.campaign_outlined,
                      color: AppColors.warning,
                      onPressed: canControl ? _sendManualTest : null,
                    )),
                  ]),
                ]),
              ),
            ),
    );
  }

  Widget _buildAlarmCard(int i) {
    final t    = _alarms[i];
    final days = _daysMask[i];
    final on   = _enabled[i];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: on ? AppColors.accent.withOpacity(0.3) : AppColors.divider,
        ),
      ),
      child: Column(children: [

        // ── TIME ROW ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(children: [
            // number badge
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: on ? AppColors.accentGlow : AppColors.divider,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(child: Text("${i + 1}",
                  style: TextStyle(
                      color: on ? AppColors.accent : AppColors.textSecondary,
                      fontWeight: FontWeight.w700, fontSize: 14))),
            ),
            const SizedBox(width: 12),
            // time
            Text(_timeText(t), style: TextStyle(
                color: on ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 28, fontWeight: FontWeight.w700,
                letterSpacing: 1)),
            const Spacer(),
            // switch
            Transform.scale(scale: 0.85,
              child: Switch(
                value: on,
                activeColor: AppColors.accent,
                inactiveThumbColor: AppColors.textSecondary,
                inactiveTrackColor: AppColors.divider,
                onChanged: canControl ? (v) => _toggleEnabled(i, v) : null,
              ),
            ),
            // edit time
            _IconBtn(icon: Icons.access_time_outlined,
                onPressed: canControl ? () => _pickTime(i) : null),
            // delete
            _IconBtn(icon: Icons.delete_outline,
                color: AppColors.error,
                onPressed: canControl ? () => _confirmDelete(i) : null),
          ]),
        ),

        Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),

        // ── MEDICINE ROW ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.successGlow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medication_rounded,
                  color: AppColors.success, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_medicineNames[i],
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500, fontSize: 14)),
                Row(children: [
                  Text("${_pillCounts[i]} เม็ด",
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  if (_notes[i].isNotEmpty) ...[
                    const Text("  ·  ",
                        style: TextStyle(color: AppColors.textSecondary)),
                    Expanded(child: Text(_notes[i],
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            fontStyle: FontStyle.italic))),
                  ],
                ]),
              ],
            )),
            _IconBtn(icon: Icons.history_outlined, color: AppColors.accent,
                onPressed: () => _showHistory(i)),
            _IconBtn(icon: Icons.edit_outlined,
                onPressed: canControl ? () => _editMedicine(i) : null),
          ]),
        ),

        // ── DAY CHIPS ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (d) {
              final sel = (days & (1 << d)) != 0;
              return GestureDetector(
                onTap: canControl ? () => _toggleDay(i, d) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36, height: 32,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.accentGlow : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? AppColors.accent.withOpacity(0.5)
                          : AppColors.divider,
                    ),
                  ),
                  child: Center(child: Text(_dayLabels[d],
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sel ? AppColors.accent : AppColors.textSecondary))),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

// ── Reusable Widgets ───────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  const _IconBtn({required this.icon, this.onPressed,
      this.color = AppColors.textSecondary});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 20, color: onPressed != null ? color : AppColors.divider),
    onPressed: onPressed,
    splashRadius: 20,
    padding: const EdgeInsets.all(8),
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  const _ActionButton({required this.label, required this.icon,
      required this.color, this.onPressed});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    style: ElevatedButton.styleFrom(
      backgroundColor: onPressed != null ? color : AppColors.card,
      foregroundColor: onPressed != null ? Colors.white : AppColors.textSecondary,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _DarkDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmLabel;
  const _DarkDialog({required this.title, required this.content,
      required this.confirmLabel});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.textPrimary,
            fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        content,
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.divider))),
            child: const Text("ยกเลิก",
                style: TextStyle(color: AppColors.textSecondary)),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text(confirmLabel, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
          )),
        ]),
      ]),
    ),
  );
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  const _DarkField({required this.controller, required this.label,
      required this.icon, this.obscure = false, this.keyboardType});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(color: AppColors.textPrimary),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      filled: true, fillColor: AppColors.bg,
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
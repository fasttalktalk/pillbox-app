import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {

  final user = FirebaseAuth.instance.currentUser;

  Map userData = {};
  bool loading = true;
  String role = "user";

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  // ─── LOAD USER ────────────────────────────────────────────
  Future<void> loadUser() async {
    final snap = await FirebaseDatabase.instance
        .ref("users/${user!.uid}")
        .get();

    if (snap.exists) {
      userData = Map<String, dynamic>.from(snap.value as Map);
      role = userData["role"] ?? "user";
    }

    setState(() => loading = false);
  }

  String formatTime(dynamic ts) {
    if (ts == null) return "-";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  // ─── CHANGE EMAIL ─────────────────────────────────────────
  Future<void> changeEmail() async {

    final newEmailCtrl    = TextEditingController(text: userData["email"] ?? user?.email ?? "");
    final newUsernameCtrl = TextEditingController(text: userData["username"] ?? "");
    final passCtrl        = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2438),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("เปลี่ยน Email",
            style: TextStyle(color: Color(0xFFEDF2FF),
                fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _darkField(controller: newUsernameCtrl, label: "Username ใหม่",
                icon: Icons.person_outline),
            const SizedBox(height: 10),
            _darkField(controller: newEmailCtrl, label: "Email ใหม่",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 10),
            _darkField(controller: passCtrl, label: "Password ปัจจุบัน",
                icon: Icons.lock_outline, obscure: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A9BC0)),
            child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text("บันทึก",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (ok != true) return;

    final newEmail    = newEmailCtrl.text.trim();
    final newUsername = newUsernameCtrl.text.trim();
    final password    = passCtrl.text;

    if (newEmail.isEmpty || !newEmail.contains("@")) {
      _showSnack("กรุณากรอก Email ให้ถูกต้อง"); return;
    }
    if (password.isEmpty) {
      _showSnack("กรุณากรอก Password เพื่อยืนยัน"); return;
    }

    try {
      final credential = EmailAuthProvider.credential(email: user!.email!, password: password);
      await user!.reauthenticateWithCredential(credential);
      await user!.updateEmail(newEmail);
      await FirebaseDatabase.instance.ref("users/${user!.uid}").update({
        "username": newUsername,
        "email": newEmail,
      });
      setState(() {
        userData["username"] = newUsername;
        userData["email"]    = newEmail;
      });
      _showSnack("✅ เปลี่ยน Email สำเร็จ");

    } on FirebaseAuthException catch (e) {
      String msg = "เกิดข้อผิดพลาด";
      if (e.code == "wrong-password")        msg = "Password ไม่ถูกต้อง";
      if (e.code == "email-already-in-use")  msg = "Email นี้ถูกใช้งานแล้ว";
      if (e.code == "requires-recent-login") msg = "กรุณา Logout แล้ว Login ใหม่ก่อน";
      _showSnack(msg);
    }
  }

  // ─── CHANGE PASSWORD ──────────────────────────────────────
  Future<void> changePassword() async {

    final currentPassCtrl = TextEditingController();
    final newPassCtrl     = TextEditingController();
    final confirmCtrl     = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2438),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("เปลี่ยนรหัสผ่าน",
            style: TextStyle(color: Color(0xFFEDF2FF),
                fontSize: 17, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _darkField(controller: currentPassCtrl, label: "Password ปัจจุบัน",
                icon: Icons.lock_open_outlined, obscure: true),
            const SizedBox(height: 10),
            _darkField(controller: newPassCtrl, label: "Password ใหม่",
                icon: Icons.lock_outline, obscure: true),
            const SizedBox(height: 10),
            _darkField(controller: confirmCtrl, label: "ยืนยัน Password ใหม่",
                icon: Icons.lock_outline, obscure: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A9BC0)),
            child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text("ยืนยัน",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (ok != true) return;

    final currentPass = currentPassCtrl.text;
    final newPass     = newPassCtrl.text;
    final confirm     = confirmCtrl.text;

    if (currentPass.isEmpty) { _showSnack("กรุณากรอก Password ปัจจุบัน"); return; }
    if (newPass.length < 6)  { _showSnack("Password ใหม่ต้องมีอย่างน้อย 6 ตัวอักษร"); return; }
    if (newPass != confirm)  { _showSnack("Password ไม่ตรงกัน"); return; }

    try {
      final credential = EmailAuthProvider.credential(email: user!.email!, password: currentPass);
      await user!.reauthenticateWithCredential(credential);
      await user!.updatePassword(newPass);
      _showSnack("✅ เปลี่ยนรหัสผ่านสำเร็จ");

    } on FirebaseAuthException catch (e) {
      String msg = "เกิดข้อผิดพลาด";
      if (e.code == "wrong-password" || e.code == "invalid-credential") {
        msg = "Password ปัจจุบันไม่ถูกต้อง";
      }
      _showSnack(msg);
    }
  }

  // ─── ADMIN: ดู User ทั้งหมด + แก้ Device + Role ──────────
  Future<void> _showAllUsers() async {

    final snap = await FirebaseDatabase.instance.ref("users").get();
    if (!snap.exists) { _showSnack("ไม่มี User ในระบบ"); return; }

    final all   = Map<String, dynamic>.from(snap.value as Map);
    final users = all.entries.map((e) {
      final m = Map<String, dynamic>.from(e.value);
      return {"uid": e.key, ...m};
    }).toList();
    users.sort((a, b) =>
        (a["username"] ?? "").toString().compareTo((b["username"] ?? "").toString()));

    if (!mounted) return;

    // color per role
    Color roleColor(String r) => r == "admin"  ? const Color(0xFF4F8EF7)
                               : r == "owner"  ? const Color(0xFFFFB347)
                               : const Color(0xFF8A9BC0);
    IconData roleIcon(String r) => r == "admin"  ? Icons.admin_panel_settings
                                 : r == "owner"  ? Icons.key_rounded
                                 : Icons.person_outline;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2438),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("User ทั้งหมด (${users.length} คน)",
            style: const TextStyle(color: Color(0xFFEDF2FF),
                fontSize: 17, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Color(0xFF232D45), height: 1),
            itemBuilder: (_, i) {
              final u             = users[i];
              final uid           = u["uid"] ?? "";
              final username      = u["username"] ?? "-";
              final email         = u["email"] ?? "-";
              final deviceId      = u["deviceId"] ?? "-";
              final userRole      = u["role"] ?? "user";
              final isCurrentUser = uid == user!.uid;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                leading: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: roleColor(userRole).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(roleIcon(userRole),
                      color: roleColor(userRole), size: 20),
                ),
                title: Row(children: [
                  Text(username, style: const TextStyle(
                      color: Color(0xFFEDF2FF), fontSize: 14,
                      fontWeight: FontWeight.w500)),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x334F8EF7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text("คุณ",
                          style: TextStyle(color: Color(0xFF4F8EF7),
                              fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleColor(userRole).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(userRole,
                        style: TextStyle(color: roleColor(userRole),
                            fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ]),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email, style: const TextStyle(
                      color: Color(0xFF8A9BC0), fontSize: 11)),
                  Text("📦 $deviceId", style: const TextStyle(
                      color: Color(0xFF8A9BC0), fontSize: 11)),
                ]),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Color(0xFF4F8EF7), size: 20),
                  tooltip: "แก้ไข",
                  onPressed: () => _editUser(uid, username, deviceId, userRole),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF232D45),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text("ปิด",
                style: TextStyle(color: Color(0xFF8A9BC0))),
          ),
        ],
      ),
    );
  }

  // แก้ทั้ง device และ role พร้อมกัน
  Future<void> _editUser(String uid, String username,
      String currentDevice, String currentRole) async {

    final devSnap    = await FirebaseDatabase.instance.ref("devices").get();
    final deviceList = devSnap.exists
        ? (Map<String, dynamic>.from(devSnap.value as Map)).keys.toList()
        : <String>[];

    if (deviceList.isEmpty) {
      _showSnack("ยังไม่มีกล่องยาในระบบ"); return;
    }

    String? selectedDevice =
        deviceList.contains(currentDevice) ? currentDevice : deviceList.first;
    String  selectedRole   = ["user","owner","admin"].contains(currentRole)
        ? currentRole : "user";

    const roles = ["user", "owner", "admin"];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1C2438),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("แก้ไข User",
                style: TextStyle(color: Color(0xFFEDF2FF),
                    fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(username,
                style: const TextStyle(color: Color(0xFF8A9BC0), fontSize: 13)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Role ──
            const Text("Role",
                style: TextStyle(color: Color(0xFF8A9BC0),
                    fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _darkDropdown<String>(
              value: selectedRole,
              items: roles,
              itemLabel: (r) => r == "user"  ? "👤 User"
                              : r == "owner" ? "🔑 Owner"
                              : "⚙️ Admin",
              onChanged: (v) => setS(() => selectedRole = v!),
            ),
            const SizedBox(height: 16),

            // ── Device ──
            const Text("กล่องยา",
                style: TextStyle(color: Color(0xFF8A9BC0),
                    fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _darkDropdown<String>(
              value: selectedDevice!,
              items: deviceList,
              itemLabel: (d) => d,
              itemIcon: const Icon(Icons.medication_liquid_outlined,
                  color: Color(0xFF4ECDC4), size: 16),
              onChanged: (v) => setS(() => selectedDevice = v),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF232D45)))),
              child: const Text("ยกเลิก",
                  style: TextStyle(color: Color(0xFF8A9BC0))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8EF7), elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text("บันทึก",
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selectedDevice == null) return;

    await FirebaseDatabase.instance.ref("users/$uid").update({
      "deviceId": selectedDevice,
      "role": selectedRole,
    });

    _showSnack("✅ อัปเดต $username สำเร็จ");
    if (uid == user!.uid) setState(() => userData["deviceId"] = selectedDevice);
  }

  // ─── HELPER: Dark Dropdown ────────────────────────────────
  Widget _darkDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
    Widget? itemIcon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF232D45)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          dropdownColor: const Color(0xFF1C2438),
          style: const TextStyle(color: Color(0xFFEDF2FF), fontSize: 14),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Color(0xFF8A9BC0)),
          items: items.map((item) => DropdownMenuItem<T>(
            value: item,
            child: Row(children: [
              if (itemIcon != null) ...[itemIcon, const SizedBox(width: 8)],
              Text(itemLabel(item)),
            ]),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _darkField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFEDF2FF)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF8A9BC0), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFF8A9BC0), size: 20),
          filled: true,
          fillColor: const Color(0xFF0A0E1A),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF232D45))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4F8EF7), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  // ─── ADMIN: จัดการกล่องยา (devices) ─────────────────────
  Future<void> _manageDevices() async {

    final snap = await FirebaseDatabase.instance.ref("devices").get();

    final devices = snap.exists
        ? Map<String, dynamic>.from(snap.value as Map)
        : <String, dynamic>{};

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1C2438),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("กล่องยา (${devices.length} กล่อง)",
              style: const TextStyle(color: Color(0xFFEDF2FF),
                  fontSize: 17, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: devices.isEmpty
                ? const Center(child: Text("ยังไม่มีกล่องยาในระบบ",
                    style: TextStyle(color: Color(0xFF8A9BC0))))
                : ListView(
                    children: devices.entries.map((e) {
                      final deviceId = e.key;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131929),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF232D45)),
                        ),
                        child: ListTile(
                          leading: const Icon(
                              Icons.medication_liquid, color: Color(0xFF4ECDC4)),
                          title: Text(deviceId,
                              style: const TextStyle(color: Color(0xFFEDF2FF))),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Color(0xFFFF6B6B)),
                            tooltip: "ลบกล่องยา",
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: ctx,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF1C2438),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  title: const Text("ยืนยันการลบ",
                                      style: TextStyle(color: Color(0xFFEDF2FF),
                                          fontSize: 17, fontWeight: FontWeight.w600)),
                                  content: Text(
                                      "ต้องการลบกล่องยา \"$deviceId\" ?",
                                      style: const TextStyle(color: Color(0xFF8A9BC0))),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF8A9BC0)),
                                      child: const Text("ยกเลิก"),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFF6B6B),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10))),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text("ลบ",
                                          style: TextStyle(color: Colors.white,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await FirebaseDatabase.instance
                                    .ref("devices/$deviceId")
                                    .remove();
                                setS(() => devices.remove(deviceId));
                                _showSnack("✅ ลบกล่องยา $deviceId แล้ว");
                              }
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A9BC0)),
              child: const Text("ปิด"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text("เพิ่มกล่องยา",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8EF7), elevation: 0,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(ctx);
                await _addDevice();
                _manageDevices();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDevice() async {

    final deviceIdCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2438),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("เพิ่มกล่องยาใหม่",
            style: TextStyle(color: Color(0xFFEDF2FF),
                fontSize: 17, fontWeight: FontWeight.w600)),
        content: _darkField(
          controller: deviceIdCtrl,
          label: "Device ID",
          icon: Icons.devices_outlined,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A9BC0)),
            child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7), elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text("เพิ่ม",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (ok != true) return;

    final deviceId = deviceIdCtrl.text.trim();
    if (deviceId.isEmpty) { _showSnack("กรุณากรอก Device ID"); return; }

    // ตรวจว่ามีอยู่แล้วไหม
    final existing = await FirebaseDatabase.instance
        .ref("devices/$deviceId")
        .get();

    if (existing.exists) {
      _showSnack("กล่องยา \"$deviceId\" มีอยู่แล้ว"); return;
    }

    // สร้าง node กล่องยาใหม่ (ว่างๆ รอ config)
    await FirebaseDatabase.instance.ref("devices/$deviceId").set({
      "createdAt": ServerValue.timestamp,
      "createdBy": user!.uid,
    });

    _showSnack("✅ เพิ่มกล่องยา \"$deviceId\" สำเร็จ");
  }

  // ─── ADMIN: อนุมัติ User ใหม่ ─────────────────────────────
  Future<void> _showPendingUsers() async {

    final snap = await FirebaseDatabase.instance.ref("pendingUsers").get();

    if (!snap.exists) {
      _showSnack("ไม่มีคำขอสมัครรอการอนุมัติ"); return;
    }

    final all = Map<String, dynamic>.from(snap.value as Map);
    final pending = all.entries.where((e) {
      final m = Map<String, dynamic>.from(e.value);
      return m["approved"] == false;
    }).toList();

    if (pending.isEmpty) {
      _showSnack("ไม่มีคำขอรอการอนุมัติ"); return;
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2438),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("รออนุมัติ (${pending.length} คน)",
            style: const TextStyle(color: Color(0xFFEDF2FF),
                fontSize: 17, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: pending.length,
            itemBuilder: (_, i) {
              final key      = pending[i].key!;
              final m        = Map<String, dynamic>.from(pending[i].value);
              final username = m["username"] ?? key;
              final email    = m["email"] ?? "-";

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131929),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF232D45)),
                ),
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0x334F8EF7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_outline,
                        color: Color(0xFF4F8EF7), size: 18),
                  ),
                  title: Text(username,
                      style: const TextStyle(color: Color(0xFFEDF2FF),
                          fontWeight: FontWeight.w500, fontSize: 14)),
                  subtitle: Text(email,
                      style: const TextStyle(color: Color(0xFF8A9BC0), fontSize: 12)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4), elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: const Text("อนุมัติ",
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    onPressed: () => _approveUser(key, m),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A9BC0)),
            child: const Text("ปิด")),
        ],
      ),
    );
  }

  Future<void> _approveUser(String key, Map<String, dynamic> m) async {

    Navigator.pop(context);

    final devSnap = await FirebaseDatabase.instance.ref("devices").get();
    final deviceList = devSnap.exists
        ? (Map<String, dynamic>.from(devSnap.value as Map)).keys.toList()
        : <String>[];

    if (deviceList.isEmpty) {
      _showSnack("ยังไม่มีกล่องยาในระบบ กรุณาเพิ่มกล่องยาก่อน"); return;
    }

    String? selectedDevice = deviceList.first;
    String  selectedRole   = "user";
    const roles = ["user", "owner", "admin"];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1C2438),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("อนุมัติ User",
                style: TextStyle(color: Color(0xFFEDF2FF),
                    fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(m["username"] ?? key,
                style: const TextStyle(color: Color(0xFF8A9BC0), fontSize: 13)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [

            // email
            Text("Email: ${m["email"] ?? "-"}",
                style: const TextStyle(color: Color(0xFF8A9BC0), fontSize: 13)),
            const SizedBox(height: 20),

            // ── Role dropdown ──
            const Text("Role",
                style: TextStyle(color: Color(0xFF8A9BC0),
                    fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _darkDropdown<String>(
              value: selectedRole,
              items: roles,
              itemLabel: (r) => r == "user"  ? "👤 User — ดูได้อย่างเดียว"
                              : r == "owner" ? "🔑 Owner — ควบคุม PillPage ได้"
                              : "⚙️ Admin — จัดการระบบได้",
              onChanged: (v) => setS(() => selectedRole = v!),
            ),
            const SizedBox(height: 16),

            // ── Device dropdown ──
            const Text("กล่องยา",
                style: TextStyle(color: Color(0xFF8A9BC0),
                    fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _darkDropdown<String>(
              value: selectedDevice!,
              items: deviceList,
              itemLabel: (d) => d,
              itemIcon: const Icon(Icons.medication_liquid_outlined,
                  color: Color(0xFF4ECDC4), size: 16),
              onChanged: (v) => setS(() => selectedDevice = v),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF232D45)))),
              child: const Text("ยกเลิก",
                  style: TextStyle(color: Color(0xFF8A9BC0))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ECDC4), elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text("ยืนยันอนุมัติ",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selectedDevice == null) return;

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: m["email"], password: m["password"],
      );
      await FirebaseDatabase.instance.ref("users/${cred.user!.uid}").set({
        "username": m["username"] ?? key,
        "email": m["email"],
        "deviceId": selectedDevice,
        "role": selectedRole,
        "approved": true,
        "approvedBy": user!.uid,
        "createdAt": m["createdAt"],
        "lastLogin": null,
      });
      await FirebaseDatabase.instance.ref("pendingUsers/$key").remove();
      _showSnack("✅ อนุมัติ ${m["username"] ?? key} เป็น $selectedRole สำเร็จ");

    } on FirebaseAuthException catch (e) {
      _showSnack(e.code == "email-already-in-use"
          ? "มี account นี้อยู่แล้ว" : "เกิดข้อผิดพลาด: ${e.code}");
    }
  }

  // ─── LOGOUT ───────────────────────────────────────────────
  Future<void> logout() async {
    // cancel Firebase listeners ก่อน signOut
    // เพื่อกัน permission-denied error ระหว่าง navigate
    await FirebaseDatabase.instance.goOffline();
    await FirebaseAuth.instance.signOut();
    await FirebaseDatabase.instance.goOnline();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1C2438),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {

    const bg             = Color(0xFF0A0E1A);
    const surface        = Color(0xFF131929);
    const card           = Color(0xFF1C2438);
    const accent         = Color(0xFF4F8EF7);
    const accentGlow     = Color(0x334F8EF7);
    const success        = Color(0xFF4ECDC4);
    const successGlow    = Color(0x334ECDC4);
    const warning        = Color(0xFFFFB347);
    const warningGlow    = Color(0x33FFB347);
    const errorColor     = Color(0xFFFF6B6B);
    const errorGlow      = Color(0x33FF6B6B);
    const textPrimary    = Color(0xFFEDF2FF);
    const textSecondary  = Color(0xFF8A9BC0);
    const divider        = Color(0xFF232D45);

    if (loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    final username  = userData["username"] ?? "-";
    final device    = userData["deviceId"] ?? "-";
    final lastLogin = formatTime(userData["lastLogin"]);
    final isAdminRole = role == "admin";

    // helper widgets
    Widget infoCard(IconData icon, String label, String value, Color iconColor, Color iconBg) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: divider),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: textSecondary, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: textPrimary,
                fontSize: 14, fontWeight: FontWeight.w500)),
          ]),
        ]),
      );
    }

    Widget actionBtn(String label, IconData icon, Color bg2, Color fg, VoidCallback fn) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: fn,
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: bg2, foregroundColor: fg,
            elevation: 0, padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("โปรไฟล์",
            style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // ── AVATAR ──
          const SizedBox(height: 8),
          Center(child: Stack(children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [accent, Color(0xFF6C63FF)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 48),
            ),
            if (isAdminRole)
              Positioned(bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentGlow, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withOpacity(0.5)),
                  ),
                  child: const Text("ADMIN",
                      style: TextStyle(color: accent, fontSize: 9,
                          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
              ),
          ])),

          const SizedBox(height: 12),
          Text(username, style: const TextStyle(
              color: textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(user?.email ?? "-",
              style: const TextStyle(color: textSecondary, fontSize: 13)),

          const SizedBox(height: 28),

          // ── INFO CARDS ──
          infoCard(Icons.devices_rounded, "กล่องยา", device, success, successGlow),
          infoCard(Icons.schedule_rounded, "เข้าสู่ระบบล่าสุด", lastLogin,
              accent, accentGlow),

          const SizedBox(height: 24),

          // ── SECTION: ตั้งค่าบัญชี ──
          Align(alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text("ตั้งค่าบัญชี",
                  style: TextStyle(color: textSecondary, fontSize: 12,
                      fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: divider),
            ),
            child: Column(children: [
              _profileMenuTile(
                icon: Icons.email_outlined, label: "เปลี่ยน Email",
                iconColor: accent, iconBg: accentGlow,
                onTap: changeEmail,
              ),
              Divider(color: divider, height: 1, indent: 56),
              _profileMenuTile(
                icon: Icons.lock_outline, label: "เปลี่ยนรหัสผ่าน",
                iconColor: warning, iconBg: warningGlow,
                onTap: changePassword,
              ),
            ]),
          ),

          // ── SECTION: สำหรับ Admin ──
          if (isAdminRole) ...[
            const SizedBox(height: 24),
            Align(alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text("จัดการระบบ",
                    style: TextStyle(color: textSecondary, fontSize: 12,
                        fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: card, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: divider),
              ),
              child: Column(children: [
                _profileMenuTile(
                  icon: Icons.people_outline_rounded, label: "จัดการ User ทั้งหมด",
                  iconColor: accent, iconBg: accentGlow,
                  onTap: _showAllUsers,
                ),
                Divider(color: divider, height: 1, indent: 56),
                _profileMenuTile(
                  icon: Icons.medication_liquid_outlined, label: "จัดการกล่องยา",
                  iconColor: success, iconBg: successGlow,
                  onTap: _manageDevices,
                ),
                Divider(color: divider, height: 1, indent: 56),
                _profileMenuTile(
                  icon: Icons.how_to_reg_outlined, label: "อนุมัติ User ใหม่",
                  iconColor: warning, iconBg: warningGlow,
                  onTap: _showPendingUsers,
                ),
              ]),
            ),
          ],

          const SizedBox(height: 24),

          // ── LOGOUT ──
          actionBtn("ออกจากระบบ", Icons.logout_rounded,
              errorGlow, errorColor, logout),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _profileMenuTile({
    required IconData icon, required String label,
    required Color iconColor, required Color iconBg,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label, style: const TextStyle(
          color: Color(0xFFEDF2FF), fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A9BC0), size: 20),
    );
  }
}
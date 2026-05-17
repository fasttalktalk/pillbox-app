import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'pill_page.dart';

// ── Design Tokens ──────────────────────────────────────────
class AppColors {
  static const bg        = Color(0xFF0A0E1A);
  static const surface   = Color(0xFF131929);
  static const card      = Color(0xFF1C2438);
  static const accent    = Color(0xFF4F8EF7);
  static const accentGlow= Color(0x334F8EF7);
  static const textPrimary   = Color(0xFFEDF2FF);
  static const textSecondary = Color(0xFF8A9BC0);
  static const error     = Color(0xFFFF6B6B);
  static const success   = Color(0xFF4ECDC4);
  static const divider   = Color(0xFF232D45);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {

  final emailController = TextEditingController();
  final passController  = TextEditingController();

  String error        = "";
  bool   loading      = false;
  bool   showPassword = false;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ─── LOGIN ────────────────────────────────────────────────
  Future<void> login() async {
    setState(() { loading = true; error = ""; });
    try {
      String input      = emailController.text.trim();
      String emailToUse = input;

      if (!input.contains("@")) {
        final snap = await FirebaseDatabase.instance
            .ref("users")
            .orderByChild("username")
            .equalTo(input)
            .limitToFirst(1)
            .get();
        if (!snap.exists) {
          setState(() { error = "ไม่พบ Username นี้ในระบบ"; loading = false; });
          return;
        }
        final userData = Map<String, dynamic>.from(
            (snap.value as Map).values.first);
        emailToUse = userData["email"] ?? "";
        if (emailToUse.isEmpty) {
          setState(() { error = "ไม่พบ Email ของ user นี้"; loading = false; });
          return;
        }
      }

      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailToUse, password: passController.text);

      final uid  = cred.user!.uid;
      final snap = await FirebaseDatabase.instance.ref("users/$uid/approved").get();

      if (snap.exists && snap.value == false) {
        await FirebaseAuth.instance.signOut();
        setState(() { error = "บัญชียังรอการอนุมัติจาก Admin"; loading = false; });
        return;
      }

      await FirebaseDatabase.instance.ref("users/$uid")
          .update({"lastLogin": ServerValue.timestamp});

      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const PillPage()));

    } on FirebaseAuthException {
      setState(() { error = "Email/Username หรือ Password ไม่ถูกต้อง"; });
    }
    setState(() => loading = false);
  }

  // ─── FORGOT PASSWORD ──────────────────────────────────────
  Future<void> _showForgotPassword() async {
    final emailCtrl = TextEditingController(text: emailController.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _darkDialog(
        title: "รีเซ็ตรหัสผ่าน",
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("ระบบจะส่ง link ไปยัง Email ของคุณ",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            _buildField(controller: emailCtrl, label: "Email",
                icon: Icons.email_outlined),
          ],
        ),
        confirmLabel: "ส่ง Link",
      ),
    );
    if (ok != true) return;
    final email = emailCtrl.text.trim();
    if (email.isEmpty || !email.contains("@")) {
      _snack("กรุณากรอก Email ให้ถูกต้อง"); return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _snack("✅ ส่ง Link ไปยัง Email แล้ว");
    } on FirebaseAuthException catch (e) {
      _snack(e.code == "user-not-found" ? "ไม่พบ Email นี้" : "เกิดข้อผิดพลาด");
    }
  }

  // ─── REGISTER ─────────────────────────────────────────────
  Future<void> _showRegisterDialog() async {
    final usernameCtrl = TextEditingController();
    final emailCtrl    = TextEditingController();
    final passCtrl     = TextEditingController();
    final confirmCtrl  = TextEditingController();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _darkDialog(
          title: "สมัครสมาชิก",
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentGlow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: AppColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      "Admin ต้องอนุมัติก่อนจึงจะ Login ได้",
                      style: TextStyle(color: AppColors.accent, fontSize: 12),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),
                _buildField(controller: usernameCtrl, label: "Username",
                    icon: Icons.person_outline),
                const SizedBox(height: 12),
                _buildField(controller: emailCtrl, label: "Email จริง",
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _buildField(
                  controller: passCtrl,
                  label: "Password",
                  icon: Icons.lock_outline,
                  obscure: obscure,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textSecondary, size: 20),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                ),
                const SizedBox(height: 12),
                _buildField(controller: confirmCtrl, label: "ยืนยัน Password",
                    icon: Icons.lock_outline, obscure: true),
              ],
            ),
          ),
          confirmLabel: "สมัคร",
          onConfirm: () => _submitRegister(
            ctx,
            usernameCtrl.text.trim(),
            emailCtrl.text.trim(),
            passCtrl.text,
            confirmCtrl.text,
          ),
          closeOnConfirm: false,
        ),
      ),
    );
  }

  Future<void> _submitRegister(BuildContext dialogCtx, String username,
      String email, String password, String confirm) async {
    if (username.isEmpty) { _snack("กรุณากรอก Username"); return; }
    if (email.isEmpty || !email.contains("@")) { _snack("กรุณากรอก Email ให้ถูกต้อง"); return; }
    if (password.length < 6) { _snack("Password ต้องมีอย่างน้อย 6 ตัวอักษร"); return; }
    if (password != confirm) { _snack("Password ไม่ตรงกัน"); return; }

    final key = email.replaceAll("@", "_at_").replaceAll(".", "_");
    await FirebaseDatabase.instance.ref("pendingUsers/$key").set({
      "username": username, "email": email, "password": password,
      "role": "user", "approved": false, "createdAt": ServerValue.timestamp,
    });

    if (!mounted) return;
    Navigator.pop(dialogCtx);
    _snack("✅ สมัครสำเร็จ! รอ Admin อนุมัติก่อน Login");
  }

  // ─── HELPERS ──────────────────────────────────────────────
  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.bg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _darkDialog({
    required String title,
    required Widget content,
    required String confirmLabel,
    VoidCallback? onConfirm,
    bool closeOnConfirm = true,
  }) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
                color: AppColors.textPrimary,
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
                      side: const BorderSide(color: AppColors.divider)),
                ),
                child: const Text("ยกเลิก",
                    style: TextStyle(color: AppColors.textSecondary)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: onConfirm ?? () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(confirmLabel,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              )),
            ]),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  const SizedBox(height: 24),

                  // ── LOGO ──
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.accentGlow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.medication_rounded,
                        color: AppColors.accent, size: 32),
                  ),

                  const SizedBox(height: 24),

                  const Text("PillBox",
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),

                  const SizedBox(height: 6),

                  const Text("จัดการยาของคุณได้ง่ายขึ้น",
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),

                  const SizedBox(height: 48),

                  // ── FIELDS ──
                  _buildField(
                    controller: emailController,
                    label: "Email หรือ Username",
                    icon: Icons.person_outline,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 14),

                  _buildField(
                    controller: passController,
                    label: "Password",
                    icon: Icons.lock_outline,
                    obscure: !showPassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary, size: 20),
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                    ),
                  ),

                  // ── FORGOT ──
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading ? null : _showForgotPassword,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent),
                      child: const Text("ลืมรหัสผ่าน?",
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── LOGIN BUTTON ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: loading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: loading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : const Text("เข้าสู่ระบบ",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── REGISTER BUTTON ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: loading ? null : _showRegisterDialog,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text("สมัครสมาชิก",
                          style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),

                  // ── ERROR ──
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(error,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import 'data.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/unity_ads_service.dart';

/// In-charge donor entry — POST /api/incharge/donors.
///
/// Flow: log in with the in-charge account (POST /api/auth/login), load
/// role + district from GET /api/auth/me, then add donors for that
/// district. The district is FORCED server-side to the in-charge's own
/// district — the app never lets the user change it, it only displays it.
/// Donors go live immediately, no approval step.
///
/// PRIVACY: the donor phone number is sent to the server (admin-only
/// there) and is never shown on any public screen. The donor photo is a
/// TINY ~120px JPEG (1-10 KB, auto-compressed by
/// [InchargeApi.pickTinyPhoto]); the server cap is 30k chars.
class InchargeDonorPage extends StatefulWidget {
  const InchargeDonorPage({super.key});

  @override
  State<InchargeDonorPage> createState() => _InchargeDonorPageState();
}

class _InchargeDonorPageState extends State<InchargeDonorPage> {
  // stage: loading | login | blocked | form
  String _stage = 'loading';
  AuthUser? _me;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loginBusy = false;
  String? _loginError;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _group = 'O+';
  String? _photoBase64;
  int _photoBytes = 0;
  String? _photoError;
  bool _submitting = false;
  String? _submitMessage;
  bool _submitOk = false;

  List<PublicDonor> _myDonors = const [];
  bool _myDonorsLoading = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _areaController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String get _district {
    final AuthUser? me = _me;
    if (me == null) return '';
    return me.district.isNotEmpty ? me.district : me.city;
  }

  /// Urdu district name for an English (Worker) district name, '' if unknown.
  String _urduDistrict(String english) {
    for (final MapEntry<String, String> e in districtEnglish.entries) {
      if (e.value == english) return e.key;
    }
    return '';
  }

  String get _province {
    final String urdu = _urduDistrict(_district);
    if (urdu.isEmpty) return '';
    for (final MapEntry<String, List<String>> e in districts.entries) {
      if (e.value.contains(urdu)) return e.key;
    }
    return '';
  }

  List<String> get _areaOptions {
    final String urdu = _urduDistrict(_district);
    if (urdu.isEmpty) return const [];
    return areas[urdu] ?? const [];
  }

  Future<void> _bootstrap() async {
    setState(() {
      _stage = 'loading';
      _loginError = null;
    });
    final AuthUser? saved = await AuthService.currentUser();
    final AuthUser? fresh = await fetchAuthMe();
    final AuthUser? me = fresh ?? saved;
    if (!mounted) return;
    if (me == null) {
      setState(() => _stage = 'login');
      return;
    }
    if (me.role.isNotEmpty && me.role != 'incharge') {
      setState(() {
        _me = me;
        _stage = 'blocked';
      });
      return;
    }
    setState(() {
      _me = me;
      _stage = 'form';
    });
    _loadMyDonors();
  }

  Future<void> _doLogin() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'ای میل اور پاس ورڈ دونوں لکھیں۔');
      return;
    }
    setState(() {
      _loginBusy = true;
      _loginError = null;
    });
    final ApiResult<(String, AuthUser)> r =
        await AuthService.login(email: email, password: password);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _loginBusy = false;
        _loginError = r.error;
      });
      return;
    }
    setState(() => _loginBusy = false);
    await _bootstrap();
  }

  Future<void> _doLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    setState(() {
      _me = null;
      _stage = 'login';
      _myDonors = const [];
    });
  }

  Future<void> _loadMyDonors() async {
    setState(() => _myDonorsLoading = true);
    final ApiResult<List<PublicDonor>> r = await InchargeApi.fetchMyDonors();
    if (!mounted) return;
    setState(() {
      _myDonorsLoading = false;
      if (r.ok) _myDonors = r.data ?? const [];
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _photoError = null);
    final PickedPhoto picked = await InchargeApi.pickTinyPhoto(source);
    if (!mounted) return;
    if (picked.cancelled) return;
    if (picked.error != null) {
      setState(() => _photoError = picked.error);
      return;
    }
    final String b64 = picked.base64 ?? '';
    setState(() {
      _photoBase64 = b64;
      _photoBytes = b64.length * 3 ~/ 4;
    });
  }

  Future<void> _submit() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    if (_district.isEmpty) {
      setState(() {
        _submitOk = false;
        _submitMessage = 'آپ کے اکاؤنٹ سے ضلع نہیں ملا — دوبارہ لاگ ان کریں۔';
      });
      return;
    }
    if (name.isEmpty || phone.isEmpty) {
      setState(() {
        _submitOk = false;
        _submitMessage = 'نام اور فون نمبر دونوں ضروری ہیں۔';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _submitMessage = null;
    });
    final ApiResult<void> r = await InchargeApi.submitDonor(
      name: name,
      phone: phone,
      province: _province,
      district: _district,
      area: _areaController.text.trim(),
      address: _addressController.text.trim(),
      group: _group,
      photoBase64: _photoBase64,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _submitOk = r.ok;
      _submitMessage = r.ok ? 'ڈونر شامل کر دیا گیا — ابھی لائیو ہے۔' : r.error;
    });
    if (r.ok) {
      _nameController.clear();
      _phoneController.clear();
      _addressController.clear();
      setState(() {
        _photoBase64 = null;
        _photoBytes = 0;
      });
      _loadMyDonors();
    }
  }

  Widget _photoSection() {
    final String? b64 = _photoBase64;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ڈونر کی تصویر (اختیاری)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'تصویر خودکار طور پر چھوٹی (~120px, 1-10 KB) کر دی جاتی ہے۔',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (b64 != null && b64.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(b64),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.person, size: 36, color: Colors.grey),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (b64 != null && b64.isNotEmpty)
                        Text(
                          'تقریباً ${(_photoBytes / 1024).toStringAsFixed(1)} KB',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('کیمرہ'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('گیلری'),
                          ),
                          if (b64 != null && b64.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _photoBase64 = null;
                                _photoBytes = 0;
                              }),
                              icon: const Icon(Icons.delete),
                              label: const Text('ہٹائیں'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_photoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _photoError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(PublicDonor donor) {
    if (donor.photo.startsWith('data:image')) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(
            base64Decode(donor.photo.split(',').last),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    if (donor.photo.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          donor.photo,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: const Color(0xFFB91C1C),
      child: Text(
        donor.group,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _loginView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.badge, size: 56, color: Color(0xFFB91C1C)),
          const SizedBox(height: 12),
          const Text(
            'انچارج لاگ ان',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'اپنے ضلع کے ڈونر شامل کرنے کے لیے انچارج اکاؤنٹ سے لاگ ان کریں۔',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'ای میل',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'پاس ورڈ',
              border: OutlineInputBorder(),
            ),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 10),
            Text(_loginError!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loginBusy ? null : _doLogin,
            child: _loginBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('لاگ ان کریں'),
          ),
          const SizedBox(height: 16),
          const Text(
            'انچارج اکاؤنٹ سوسائٹی ایڈمن بناتا ہے — یہاں خود سے رجسٹر نہ کریں۔',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _blockedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'یہ اکاؤنٹ انچارج کا نہیں ہے (role: ${_me?.role ?? ''})۔',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'ڈونر صرف اپنے ضلع کا انچارج شامل کر سکتا ہے۔',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _doLogout,
              child: const Text('لاگ آؤٹ کریں'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView() {
    final List<String> areaOptions = _areaOptions;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 1,
            child: ListTile(
              leading: const Icon(Icons.account_circle, size: 40),
              title: Text(_me?.name ?? ''),
              subtitle: Text(
                'ضلع: ${_district.isEmpty ? '—' : _district} (سرور طے کرتا ہے)',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'لاگ آؤٹ',
                onPressed: _doLogout,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'ڈونر کا نام *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'فون نمبر * (صرف ایڈمن دیکھتا ہے)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _group,
            decoration: const InputDecoration(
              labelText: 'بلڈ گروپ',
              border: OutlineInputBorder(),
            ),
            items: bloodGroups
                .map(
                  (String g) => DropdownMenuItem<String>(
                    value: g,
                    child: Text(g),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              if (value != null) setState(() => _group = value);
            },
          ),
          const SizedBox(height: 12),
          if (areaOptions.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: areaOptions.contains(_areaController.text)
                  ? _areaController.text
                  : null,
              decoration: const InputDecoration(
                labelText: 'علاقہ',
                border: OutlineInputBorder(),
              ),
              items: areaOptions
                  .map(
                    (String a) => DropdownMenuItem<String>(
                      value: a,
                      child: Text(a),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _areaController.text = value);
                }
              },
            )
          else
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(
                labelText: 'علاقہ',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'پتہ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _photoSection(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.add),
            label: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ڈونر شامل کریں'),
          ),
          if (_submitMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _submitMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _submitOk ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'میرے ضلع کے ڈونر (${_myDonors.length})',
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _myDonorsLoading ? null : _loadMyDonors,
              ),
            ],
          ),
          if (_myDonorsLoading)
            const Center(child: CircularProgressIndicator())
          else if (_myDonors.isEmpty)
            const Text('ابھی کوئی ڈونر نہیں۔')
          else
            Column(
              children: _myDonors.map((PublicDonor donor) {
                return Card(
                  elevation: 1,
                  child: ListTile(
                    leading: _thumb(donor),
                    title: Text(donor.name),
                    subtitle: Text(
                      '${donor.district}${donor.area.isNotEmpty ? ' • ${donor.area}' : ''}',
                    ),
                    trailing: Text(
                      donor.group,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('In-charge • ڈونر شامل کریں')),
      bottomNavigationBar: ZonedUnityBanner(zone: (ads) => ads.bannerIncharge),
      body: _stage == 'loading'
          ? const Center(child: CircularProgressIndicator())
          : _stage == 'login'
              ? _loginView()
              : _stage == 'blocked'
                  ? _blockedView()
                  : _formView(),
    );
  }
}

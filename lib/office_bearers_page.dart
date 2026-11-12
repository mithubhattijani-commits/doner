import 'dart:convert';

import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'services/unity_ads_service.dart';

/// Office-bearers page — GET /api/office-bearers.
///
/// The list is data-driven from the API: every post the server returns is
/// shown (founder, spokesperson, director, secretary, chairman, president,
/// treasurer, ...). No post list is hardcoded anywhere.
///
/// PRIVACY: the call is made WITHOUT showPhone, so the server sends no
/// phone numbers. If a phone number ever arrives in a payload, it is
/// rendered ONLY for the founder ([OfficeBearer.showPhone]) — never for
/// any other post, not even the spokesperson.
class OfficeBearersPage extends StatefulWidget {
  const OfficeBearersPage({super.key});

  @override
  State<OfficeBearersPage> createState() => _OfficeBearersPageState();
}

class _OfficeBearersPageState extends State<OfficeBearersPage> {
  List<OfficeBearer> _bearers = const [];
  bool _loading = true;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<OfficeBearer> bearers =
        await InchargeApi.fetchOfficeBearers();
    if (!mounted) return;
    setState(() {
      _bearers = bearers;
      _loading = false;
      _loadedOnce = true;
    });
  }

  Widget _photoAvatar(OfficeBearer bearer) {
    const double size = 58;
    if (bearer.photo.isEmpty) {
      return _initialAvatar(bearer, size);
    }
    if (bearer.photo.startsWith('data:image')) {
      try {
        final String b64 = bearer.photo.split(',').last;
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(base64Decode(b64)),
        );
      } catch (_) {
        return _initialAvatar(bearer, size);
      }
    }
    if (bearer.photo.startsWith('http')) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(bearer.photo),
        onBackgroundImageError: (_, __) {},
      );
    }
    return _initialAvatar(bearer, size);
  }

  Widget _initialAvatar(OfficeBearer bearer, double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFB91C1C),
      child: Text(
        bearer.name.isEmpty ? '؟' : bearer.name[0],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Office Bearers • عہدیداران'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      bottomNavigationBar: ZonedUnityBanner(zone: (ads) => ads.bannerOfficeBearers),
      body: _loading && !_loadedOnce
          ? const Center(child: CircularProgressIndicator())
          : _bearers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ابھی کوئی عہدیدار درج نہیں۔',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('دوبارہ کوشش کریں'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _bearers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final OfficeBearer bearer = _bearers[index];
                      return Card(
                        elevation: 1,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          leading: _photoAvatar(bearer),
                          title: Text(
                            bearer.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bearer.post,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (bearer.showPhone)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.phone,
                                        size: 15,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(bearer.phone),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

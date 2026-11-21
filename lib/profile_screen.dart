
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'private_config.dart';
class ProfileScreen extends StatefulWidget {
  final bool isDark;

  const ProfileScreen({
    super.key,
    required this.isDark,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color pink = Color(0xFFFF4FA3);
  static const Color purple = Color(0xFF7C3AED);

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _partnerController = TextEditingController();
  final _coupleIdController = TextEditingController();

  DateTime? _anniversaryDate;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  User? get _user => FirebaseAuth.instance.currentUser;

  DocumentReference<Map<String, dynamic>> get _profileRef {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _partnerController.dispose();
    _coupleIdController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _user;

      if (user == null) {
        throw Exception('Please login again.');
      }

      final snapshot = await _profileRef.get();

      if (snapshot.exists) {
        final data = snapshot.data()!;

        _nameController.text = data['displayName'] ?? '';
        _partnerController.text = data['partnerName'] ?? '';
        _coupleIdController.text = data['coupleId'] ?? '';

        final date = data['anniversaryDate'];

        if (date is String && date.isNotEmpty) {
          _anniversaryDate = DateTime.tryParse(date);
        }
      }
    } catch (e) {
      _errorMessage = 'Profile load failed. Please try again.';
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _dateForDatabase(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectAnniversary() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _anniversaryDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select Anniversary Date',
      builder: (context, child) {
        return Theme(
          data: widget.isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: pink,
                    secondary: purple,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: pink,
                    secondary: purple,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (selected != null) {
      setState(() {
        _anniversaryDate = selected;
      });
    }
  }

  Future<void> _createCoupleInvite() async {
    const ramUid =AppPrivateConfig.ramUid;

    final user = _user;

    if (user == null || user.uid != ramUid) {
      return;
    }

    try {
      final random = math.Random.secure();

      final bytes = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      );

      final inviteCode = base64Url.encode(bytes).replaceAll('=', '');

      await FirebaseFirestore.instance
          .collection('couple_invites')
          .doc(inviteCode)
          .set({
        'ownerUid': user.uid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 24)),
        ),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Your Couple Invite ❤️'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Share this secure code with SWATI.'),
                const SizedBox(height: 16),
                SelectableText(
                  inviteCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This invitation expires in 24 hours.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: inviteCode),
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite code copied!'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Code'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite Error: ${e.code}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to create invite. Please try again.'),
        ),
      );
    }
  }

  // SWATI ONLY - JOIN COUPLE
  Future<void> _joinCouple() async {
    const ramUid =AppPrivateConfig.ramUid;
    const swatiUid = AppPrivateConfig.swatiUid;

    final user = _user;

    if (user == null || user.uid != swatiUid || _saving) {
      return;
    }

    final codeController = TextEditingController();

    final enteredCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Join Our Couple ❤️'),
          content: TextField(
            controller: codeController,
            maxLength: 43,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Enter Invite Code',
              hintText: 'Paste your invite code',
              prefixIcon: Icon(Icons.vpn_key_rounded),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  codeController.text.trim(),
                );
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );

    codeController.dispose();

    if (!mounted || enteredCode == null) return;

    final inviteCode = enteredCode.trim();

    if (inviteCode.length != 43 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(inviteCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Invite Code. Please check again.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = FirebaseFirestore.instance;

      final inviteRef = db
          .collection('couple_invites')
          .doc(inviteCode);

      final inviteSnapshot = await inviteRef.get();

      if (!inviteSnapshot.exists) {
        throw Exception('Invalid invitation.');
      }

      final inviteData = inviteSnapshot.data()!;
      final expiresAt = inviteData['expiresAt'];

      if (inviteData['ownerUid'] != ramUid ||
          inviteData['status'] != 'pending' ||
          expiresAt is! Timestamp ||
          !expiresAt.toDate().isAfter(DateTime.now())) {
        throw Exception('Invitation is expired or already used.');
      }

      final coupleRef = db
          .collection('couples')
          .doc('private_chat');

      final batch = db.batch();

      batch.set(coupleRef, {
        'ownerUid': ramUid,
        'partnerUid': user.uid,
        'memberUids': [
          ramUid,
          user.uid,
        ],
        'inviteCode': inviteCode,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'joinedAt': FieldValue.serverTimestamp(),
      });

      batch.update(inviteRef, {
        'status': 'active',
        'joinedByUid': user.uid,
        'coupleId': 'private_chat',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are now connected as a couple! ❤️'),
          backgroundColor: Color(0xFF269B72),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Join failed: ${e.code}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_anniversaryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your Anniversary Date.'),
        ),
      );
      return;
    }

    final user = _user;

    if (user == null) return;

    setState(() {
      _saving = true;
    });

    try {
      await _profileRef.set({
        'uid': user.uid,
        'displayName': _nameController.text.trim(),
        'partnerName': _partnerController.text.trim(),
        'coupleId': _coupleIdController.text.trim(),
        'anniversaryDate': _dateForDatabase(_anniversaryDate!),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully! ❤️'),
          backgroundColor: Color(0xFF269B72),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase Error: ${e.code}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save profile. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _initial(String name) {
    final value = name.trim();
    return value.isEmpty ? '?' : value[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;

    final background = dark
        ? const [Color(0xFF10091F), Color(0xFF25103B), Color(0xFF3C1745)]
        : const [Color(0xFFFFF5FA), Color(0xFFF4E8FF), Color(0xFFFFE1EF)];

    final textColor = dark ? Colors.white : const Color(0xFF351343);

    final mutedColor = dark ? Colors.white60 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Our Profile ❤️',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: background,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: pink),
                )
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: textColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 65, 20, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildProfileHeader(textColor, mutedColor),
                            const SizedBox(height: 28),

                            _sectionTitle(
                              'YOUR LITTLE UNIVERSE',
                              textColor,
                            ),
                            const SizedBox(height: 14),

                            _buildAvatarSection(
                              textColor,
                              mutedColor,
                            ),
                            const SizedBox(height: 24),

                            _sectionTitle('PROFILE DETAILS', textColor),
                            const SizedBox(height: 14),

                            _buildField(
                              label: 'Your Name',
                              hint: 'Enter your name',
                              icon: Icons.person_outline_rounded,
                              controller: _nameController,
                            ),
                            const SizedBox(height: 14),

                            _buildField(
                              label: 'Partner Name',
                              hint: 'Enter partner name',
                              icon: Icons.favorite_border_rounded,
                              controller: _partnerController,
                            ),
                            const SizedBox(height: 14),

                            _buildField(
                              label: 'Couple ID',
                              hint: 'Enter your Couple ID',
                              icon: Icons.fingerprint_rounded,
                              controller: _coupleIdController,
                            ),
                            const SizedBox(height: 20),

                            _sectionTitle('OUR SPECIAL DAY', textColor),
                            const SizedBox(height: 14),

                            _buildAnniversaryCard(
                              textColor,
                              mutedColor,
                            ),
                            const SizedBox(height: 28),

                            // RAM ONLY - CREATE COUPLE INVITE
                            if (_user?.uid ==
                               AppPrivateConfig.ramUid) ...[
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : _createCoupleInvite,
                                  icon: const Icon(Icons.link_rounded),
                                  label: const Text(
                                    'Create Couple Invite',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: pink,
                                    side: const BorderSide(color: pink),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // SWATI ONLY - JOIN COUPLE
                            if (_user?.uid ==
                                AppPrivateConfig.swatiUid) ...[
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _joinCouple,
                                  icon: const Icon(Icons.favorite_rounded),
                                  label: const Text(
                                    'Join Couple',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: pink,
                                    side: const BorderSide(color: pink),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            SizedBox(
                              height: 56,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [purple, pink],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: pink.withValues(alpha: 0.25),
                                      blurRadius: 18,
                                      offset: const Offset(0, 7),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  icon: _saving
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_rounded),
                                  label: Text(
                                    _saving ? 'Saving...' : 'Save Profile',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 30),

                            Text(
                              'Made with ❤️ for two hearts',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: mutedColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 10),

                            const Text(
                              'Powered by Rtechnologies',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: pink,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Color textColor, Color mutedColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [purple, pink],
            ),
            boxShadow: [
              BoxShadow(
                color: pink.withValues(alpha: 0.25),
                blurRadius: 25,
              ),
            ],
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: Colors.white,
            size: 42,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Together Forever',
          style: TextStyle(
            color: textColor,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your story, your memories, your love.',
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedColor, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildAvatarSection(Color textColor, Color mutedColor) {
    return Row(
      children: [
        Expanded(
          child: _avatarCard(
            title: 'YOU',
            name: _nameController.text,
            icon: Icons.person_rounded,
            textColor: textColor,
            mutedColor: mutedColor,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.favorite_rounded,
            color: pink,
            size: 25,
          ),
        ),
        Expanded(
          child: _avatarCard(
            title: 'PARTNER',
            name: _partnerController.text,
            icon: Icons.person_rounded,
            textColor: textColor,
            mutedColor: mutedColor,
          ),
        ),
      ],
    );
  }

  Widget _avatarCard({
    required String title,
    required String name,
    required IconData icon,
    required Color textColor,
    required Color mutedColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: pink.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 65,
            width: 65,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [purple, pink],
              ),
            ),
            child: Center(
              child: Text(
                name.trim().isEmpty ? '♡' : _initial(name),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: pink,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name.trim().isEmpty ? 'Add name below' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    final dark = widget.isDark;

    return TextFormField(
      controller: controller,
      maxLength: label == 'Couple ID' ? 40 : 60,
      style: TextStyle(
        color: dark ? Colors.white : const Color(0xFF351343),
      ),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: pink),
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.8),
        labelStyle: TextStyle(
          color: dark ? Colors.white70 : Colors.black54,
        ),
        hintStyle: TextStyle(
          color: dark ? Colors.white38 : Colors.black38,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: pink.withValues(alpha: 0.18),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(
            color: pink,
            width: 1.5,
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label is required';
        }
        return null;
      },
    );
  }

  Widget _buildAnniversaryCard(
    Color textColor,
    Color mutedColor,
  ) {
    return InkWell(
      onTap: _selectAnniversary,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              purple.withValues(alpha: widget.isDark ? 0.35 : 0.12),
              pink.withValues(alpha: widget.isDark ? 0.25 : 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pink.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              color: pink,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Anniversary Date',
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _anniversaryDate == null
                        ? 'Select your special day'
                        : _formatDate(_anniversaryDate!),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_calendar_rounded,
              color: pink,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'background_service.dart';
import 'firebase_options.dart';
import 'our_map_screen.dart';
import 'profile_screen.dart';
const Color pink = Color(0xFFFF4FA3);
const Color purple = Color(0xFF7C3AED);
const Color deep = Color(0xFF10091F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeService();

  runApp(const UsOnMapApp());
}
class UsOnMapApp extends StatefulWidget {
  const UsOnMapApp({super.key});

  @override
  State<UsOnMapApp> createState() => _UsOnMapAppState();
}

class _UsOnMapAppState extends State<UsOnMapApp> {
  ThemeMode themeMode = ThemeMode.dark;
  bool showHome = false;

  void changeTheme(bool isDark) {
    setState(() => themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UsOnMap',
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 700),
      themeAnimationCurve: Curves.easeInOutCubic,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: pink,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF5FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFF5FA),
          foregroundColor: Color(0xFF351343),
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: pink,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: deep,
        appBarTheme: const AppBarTheme(
          backgroundColor: deep,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: showHome
          ? StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingScreen();
                }
                if (snapshot.hasData) {
                  return HomeScreen(isDark: isDark, onThemeChanged: changeTheme);
                }
                return const AuthScreen();
              },
            )
          : SplashScreen(onFinished: () {
              if (mounted) setState(() => showHome = true);
            }),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: pink)),
      );
}

// Animated splash screen
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController heartController;
  late final AnimationController glowController;
  late final Animation<double> heartScale;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    heartScale = Tween<double>(begin: 0.90, end: 1.12).animate(
      CurvedAnimation(parent: heartController, curve: Curves.easeInOut),
    );
    glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    timer = Timer(const Duration(seconds: 4), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    heartController.dispose();
    glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10091F), Color(0xFF32104D), Color(0xFF851F70), Color(0xFFEF438E)],
            stops: [0.0, 0.42, 0.75, 1.0],
          ),
        ),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: glowController,
              builder: (context, child) {
                final t = glowController.value * 2 * math.pi;
                return Stack(children: [
                  Positioned(top: 100 + 18 * math.sin(t), left: 35, child: const GlowOrb(size: 90)),
                  Positioned(right: 15, top: 300 + 25 * math.cos(t), child: const GlowOrb(size: 120)),
                  Positioned(left: 80, bottom: 150 + 15 * math.sin(t), child: const GlowOrb(size: 65)),
                ]);
              },
            ),
            SafeArea(
              child: Column(children: [
                const Spacer(flex: 2),
                AnimatedBuilder(
                  animation: heartScale,
                  builder: (context, child) => Transform.scale(
                    scale: heartScale.value,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        boxShadow: [BoxShadow(color: pink.withValues(alpha: 0.45), blurRadius: 50, spreadRadius: 5)],
                      ),
                      child: const Icon(Icons.favorite_rounded, size: 92, color: pink),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'UsOn', style: TextStyle(color: Colors.white)),
                    TextSpan(text: 'Map', style: TextStyle(color: Color(0xFFFF77C4))),
                    TextSpan(text: ' ♥', style: TextStyle(color: pink)),
                  ]),
                  style: TextStyle(fontSize: 39, fontWeight: FontWeight.w800, letterSpacing: -1),
                ),
                const SizedBox(height: 12),
                const Text('Your world, together.', style: TextStyle(fontSize: 17, color: Colors.white70, letterSpacing: 1.1)),
                const Spacer(flex: 2),
                const Text('CONNECTING HEARTS', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 3)),
                const SizedBox(height: 16),
                SizedBox(width: 150, child: ClipRRect(borderRadius: BorderRadius.circular(20), child: const LinearProgressIndicator(minHeight: 4, color: pink, backgroundColor: Color(0x667C3AED)))),
                const Spacer(),
                const RTechFooter(),
                const SizedBox(height: 22),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class GlowOrb extends StatelessWidget {
  final double size;
  const GlowOrb({super.key, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [pink.withValues(alpha: 0.20), purple.withValues(alpha: 0.03), Colors.transparent]),
          ),
        ),
      );
}

// Home dashboard
class HomeScreen extends StatelessWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const HomeScreen({super.key, required this.isDark, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    final backgroundColors = isDark
        ? const [deep, Color(0xFF25103B), Color(0xFF3C1745)]
        : const [Color(0xFFFFF5FA), Color(0xFFF4E8FF), Color(0xFFFFE1EF)];
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'UsOn'),
          TextSpan(text: 'Map ♥', style: TextStyle(color: pink)),
        ]), style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Change theme', onPressed: () => onThemeChanged(!isDark), icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded)),
          IconButton(tooltip: 'Sign out', onPressed: () async => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: backgroundColors)),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              const HomeMessageNotifier(),
              Text('A little world for two ✨', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 14)),
              const SizedBox(height: 8),
              Text('Your world,\ntogether.', style: TextStyle(fontSize: 34, height: 1.12, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF351343))),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF9D36A7), Color(0xFFE74791)]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: pink.withValues(alpha: 0.20), blurRadius: 22, offset: const Offset(0, 8))],
                ),
                child: const Row(children: [
                  Icon(Icons.favorite_rounded, color: Colors.white, size: 42),
                  SizedBox(width: 15),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Made for two hearts', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 7),
                    Text('Share moments. Keep memories close.', style: TextStyle(color: Colors.white70)),
                  ])),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('OUR LITTLE UNIVERSE', style: TextStyle(color: pink, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.98,
                children: [
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('private_chats')
                        .doc('private_chat')
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .limit(150)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      final hasUnreadMessage = uid != null &&
                          (snapshot.data?.docs ?? []).any((doc) {
                            final data = doc.data();
                            final readBy = data['readBy'];
                            return data['senderId'] != uid &&
                                !(readBy is List && readBy.contains(uid));
                          });
                      return FeatureCard(
                        icon: Icons.chat_bubble_rounded,
                        title: 'Private Chat',
                        subtitle: 'Just us two',
                        color: const Color(0xFFE74791),
                        showBadge: hasUnreadMessage,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PrivateChatScreen(isDark: isDark),
                          ),
                        ),
                      );
                    },
                  ),
                  FeatureCard(icon: Icons.location_on_rounded, title: 'Our Map', subtitle: 'Share live location', color: const Color(0xFF3977F6), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OurMapScreen()))),                 
                  FeatureCard(
  icon: Icons.favorite_rounded,
  title: 'Our Profile',
  subtitle: 'Your couple details',
  color: const Color(0xFFE84A9B),
  onTap: () => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProfileScreen(isDark: isDark),
    ),
  ),
),
                  FeatureCard(icon: Icons.auto_awesome_rounded, title: 'Memories', subtitle: 'Our best moments', color: const Color(0xFFFF914D), onTap: () => showInfo(context, 'Memories')),
                  FeatureCard(icon: Icons.notifications_active_rounded, title: 'Notifications', subtitle: 'Stay connected', color: const Color(0xFF00BDAA), onTap: () => showInfo(context, 'Notifications')),
                ],
              ),
              const SizedBox(height: 22),
              Text('Better together ♡', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF6E3476), fontSize: 19, fontStyle: FontStyle.italic)),
              const SizedBox(height: 14),
              const RTechFooter(),
            ],
          ),
        ),
      ),
    );
  }

  static void showInfo(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature — Coming soon!'), behavior: SnackBarBehavior.floating));
  }
}

// Private chat: text, compressed photo, camera, shared location, typing and presence.
// Photos are stored inline in Firestore, so compress them aggressively first.
class PrivateChatScreen extends StatefulWidget {
  final bool isDark;
  const PrivateChatScreen({super.key, required this.isDark});

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _sending = false;
  Timer? _typingTimer;
  Timer? _presenceTimer;
  bool _lastTypingValue = false;
  static const int _maxPhotoBytes = 180 * 1024; // encoded document stays comfortably below 1 MiB

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _room => FirebaseFirestore.instance.collection('private_chats').doc('private_chat');
  CollectionReference<Map<String, dynamic>> get _messages => _room.collection('messages');
  CollectionReference<Map<String, dynamic>> get _presence => _room.collection('presence');
  CollectionReference<Map<String, dynamic>> get _typing => _room.collection('typing');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setPresence(true);
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) => _setPresence(true));
   _messages
    .orderBy('createdAt', descending: true)
    .limit(30)
    .get()
    .then((snapshot) async {
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final deliveredBy = List<String>.from(
      data['deliveredBy'] ?? const [],
    );

    if (data['senderId'] != _uid &&
        !deliveredBy.contains(_uid)) {
      try {
        await doc.reference.update({
          'deliveredBy': FieldValue.arrayUnion([_uid]),
        });
      } catch (e) {
        debugPrint('DELIVERED STATUS ERROR: $e');
      }
    }
  }
}).catchError((e) {
  debugPrint('LOAD DELIVERED MESSAGES ERROR: $e');
});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setPresence(true);
    } else {
      _setPresence(false);
    }
  }

  Future<void> _setPresence(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _presence.doc(user.uid).set({
        'uid': user.uid,
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
   } catch (e) {
  debugPrint('PRESENCE WRITE ERROR: $e');
}
  }

  Future<void> _setTyping(bool typing) async {
    if (_lastTypingValue == typing) return;
    _lastTypingValue = typing;
    try {
      await _typing.doc(_uid).set({'uid': _uid, 'typing': typing, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  } catch (e) {
  debugPrint('TYPING WRITE ERROR: $e');
}
  }

  void _onTextChanged(String value) {
    _setTyping(value.trim().isNotEmpty);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () => _setTyping(false));
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _presenceTimer?.cancel();
    _setTyping(false);
    _setPresence(false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
Future<void> _deleteMessage(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text('Choose an option.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'me'),
          child: const Text('Delete for me'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'everyone'),
          child: const Text('Delete for everyone'),
        ),
      ],
    ),
  );

  if (action == null || action == 'cancel' || !mounted) return;

  try {
    if (action == 'me') {
      await doc.reference.update({
        'hiddenBy': FieldValue.arrayUnion([_uid]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted for you.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'everyone') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete for everyone?'),
          content: const Text(
            'This message will be deleted for both participants.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await doc.reference.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted for everyone.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  } on FirebaseException catch (e) {
    debugPrint('DELETE MESSAGE ERROR: ${e.code} | ${e.message}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete message: ${e.code}')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete message.')),
      );
    }
  }
  
}
  Future<void> _clearAllChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete the entire chat?'),
        content: const Text('All messages in this chat will be permanently deleted from Firestore. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // Delete in batches of at most 400 so larger chats do not exceed Firestore's batch limit.
      while (true) {
        final snapshot = await _messages.limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The entire chat was deleted.')));
    } on FirebaseException catch (e) {
      debugPrint('CLEAR CHAT ERROR: ${e.code} | ${e.message}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == 'permission-denied'
          ? 'Permission to delete all messages was denied. Check Firestore rules.'
          : 'The chat could not be fully deleted: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting chat: $e')));
    }
  }

  Future<void> _sendMessage({String? text, String? photoBase64, String? photoMime, double? latitude, double? longitude}) async {
    final messageText = (text ?? _messageController.text).trim();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _sending || (messageText.isEmpty && photoBase64 == null && latitude == null)) return;
    setState(() => _sending = true);
    if (text == null && photoBase64 == null && latitude == null) _messageController.clear();
    try {
      await _messages.add({
        'text': messageText,
        'senderId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'deliveredBy': <String>[],
        'readBy': <String>[],
        if (photoBase64 != null) 'photoBase64': photoBase64,
        if (photoMime != null) 'photoMime': photoMime,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (latitude != null) 'type': 'location',
        if (photoBase64 != null) 'type': 'photo',
        if (photoBase64 == null && latitude == null) 'type': 'text',
      });
      await _setTyping(false);
    } on FirebaseException catch (e) {
      debugPrint('SEND MESSAGE ERROR: ${e.code} | ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == 'permission-denied'
            ? 'Check Firestore read/write permissions for the new features.'
            : 'Could not send the message: ${e.message ?? e.code}')));
      }
      if (text == null && photoBase64 == null && latitude == null) _messageController.text = messageText;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 45, maxWidth: 1000, maxHeight: 1000);
      if (picked == null) return;
      final compressed = await FlutterImageCompress.compressWithFile(picked.path, quality: 45, minWidth: 900, minHeight: 900, format: CompressFormat.jpeg);
      if (compressed == null || compressed.isEmpty) throw Exception('Could not compress the photo.');
      if (compressed.length > _maxPhotoBytes) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The photo is too large. Please choose a lower-resolution image.')));
        return;
      }
      await _sendMessage(photoBase64: base64Encode(compressed), photoMime: 'image/jpeg', text: '');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send the photo: $e')));
    }
  }

  Future<void> _showPhotoOptions() async {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose photo from gallery'), onTap: () { Navigator.pop(sheetContext); _pickPhoto(ImageSource.gallery); }),
      ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'), onTap: () { Navigator.pop(sheetContext); _pickPhoto(ImageSource.camera); }),
    ])));
  }

  Future<void> _shareLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Turn on Location/GPS on your phone.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Allow location permission in Settings.');
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await _sendMessage(latitude: position.latitude, longitude: position.longitude, text: 'My current location 📍');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share location: $e')));
    }
  }

  Future<void> _openLocation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Maps.')));
    }
  }

  String _lastSeenText(Map<String, dynamic>? data) {
    if (data == null) return 'Offline';
    if (data['online'] == true) return 'Online';
    final ts = data['lastSeen'];
    if (ts is! Timestamp) return 'Offline';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'Last seen: just now';
    if (d.inHours < 1) return 'Last seen: ${d.inMinutes} minutes ago';
    if (d.inDays < 1) return 'Last seen: ${d.inHours} hours ago';
    return 'Last seen: ${d.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final bg = isDark ? const [deep, Color(0xFF25103B), Color(0xFF3C1745)] : const [Color(0xFFFFF5FA), Color(0xFFF4E8FF), Color(0xFFFFE1EF)];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Chat ♥', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Clear All Chat',
            onPressed: _clearAllChat,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg)),
        child: SafeArea(child: Column(children: [
          StreamBuilder<Map<String, dynamic>?>(
            stream: _presence.snapshots().map((snap) { final docs = snap.docs.where((d) => d.id != currentUid); return docs.isEmpty ? null : docs.first.data(); }),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(14, 8, 14, 5), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(16), border: Border.all(color: pink.withValues(alpha: 0.25))), child: Row(children: [Icon(Icons.circle, size: 9, color: data?['online'] == true ? Colors.greenAccent : Colors.grey), const SizedBox(width: 8), Expanded(child: Text(_lastSeenText(data), style: const TextStyle(fontWeight: FontWeight.w600))), const Icon(Icons.favorite_rounded, color: pink)]));
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _typing.snapshots(),
            builder: (context, snapshot) {
              final isTyping = (snapshot.data?.docs ?? []).any((d) => d.id != currentUid && d.data()['typing'] == true);
              if (!isTyping) return const SizedBox(height: 4);
              return const Padding(padding: EdgeInsets.only(bottom: 5), child: Text('Your partner is typing…', style: TextStyle(color: pink, fontSize: 12, fontStyle: FontStyle.italic)));
            },
          ),
          Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _messages.orderBy('createdAt', descending: true).limit(150).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load chat. Check the Firestore database and rules.\n\n${snapshot.error}', textAlign: TextAlign.center)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: pink));
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_rounded, size: 54, color: pink.withValues(alpha: 0.85)), const SizedBox(height: 12), const Text('Send the first message ❤️', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Your messages will appear here.', textAlign: TextAlign.center)])));
              for (final doc in docs) {
                final data = doc.data();
                if (data['senderId'] != currentUid && !(data['readBy'] is List && (data['readBy'] as List).contains(currentUid))) {
                  doc.reference.set({'readBy': FieldValue.arrayUnion([currentUid])}, SetOptions(merge: true)).catchError((_) {});
                }
              }
              return ListView.builder(controller: _scrollController, reverse: true, padding: const EdgeInsets.fromLTRB(14, 8, 14, 16), itemCount: docs.length, itemBuilder: (context, index) {
                final doc = docs[index]; final data = doc.data(); final mine = data['senderId'] == currentUid;
                final message = (data['text'] as String?) ?? ''; final timestamp = data['createdAt'];
                final time = timestamp is Timestamp ? TimeOfDay.fromDateTime(timestamp.toDate()).format(context) : '…';
                final photo = data['photoBase64'] as String?;
                final lat = data['latitude']; final lng = data['longitude'];
                final readBy = data['readBy'] is List && (data['readBy'] as List).any((v) => v != data['senderId']);
                return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(
                  onLongPress: () => _deleteMessage(doc),
                  child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78), margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
                  decoration: BoxDecoration(gradient: mine ? const LinearGradient(colors: [Color(0xFF9D36A7), Color(0xFFE74791)]) : null, color: mine ? null : (isDark ? const Color(0xFF30213D) : Colors.white.withValues(alpha: 0.90)), borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (photo != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(photo), fit: BoxFit.cover, width: 230, errorBuilder: (_, __, ___) => const Text('Could not display photo'))),
                    if (lat is num && lng is num) InkWell(onTap: () => _openLocation(lat.toDouble(), lng.toDouble()), child: Container(width: 220, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: mine ? Colors.white.withValues(alpha: 0.15) : pink.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.location_on_rounded, color: pink, size: 32), const SizedBox(width: 8), Expanded(child: Text('Open location\nTap to view in Google Maps', style: TextStyle(color: mine ? Colors.white : (isDark ? Colors.white : const Color(0xFF351343)), fontWeight: FontWeight.w600)))]))),
                    if (message.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(message, style: TextStyle(color: mine ? Colors.white : (isDark ? Colors.white : const Color(0xFF351343)), fontSize: 15)))),
                    const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [Text(time, style: TextStyle(color: mine ? Colors.white70 : (isDark ? Colors.white54 : Colors.black45), fontSize: 10)), if (mine) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.done_all_rounded, size: 15, color: readBy ? const Color(0xFF9CF7FF) : Colors.white70))]),
                  ]),
                  ),
                ));
              });
            },
          )),
          Container(padding: const EdgeInsets.fromLTRB(8, 8, 8, 10), decoration: BoxDecoration(color: isDark ? const Color(0xFF170D25).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.88), border: Border(top: BorderSide(color: pink.withValues(alpha: 0.18)))), child: Row(children: [
            IconButton(tooltip: 'Photo / Camera', onPressed: _showPhotoOptions, icon: const Icon(Icons.add_photo_alternate_rounded, color: pink)),
            IconButton(tooltip: 'Live location share', onPressed: _shareLocation, icon: const Icon(Icons.location_on_rounded, color: Color(0xFF3977F6))),
            Expanded(child: TextField(controller: _messageController, minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences, onChanged: _onTextChanged, onSubmitted: (_) => _sendMessage(), decoration: InputDecoration(hintText: 'Type a message...', filled: true, fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFFFF5FA), contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
            const SizedBox(width: 5), IconButton.filled(onPressed: _sending ? null : () => _sendMessage(), style: IconButton.styleFrom(backgroundColor: pink, foregroundColor: Colors.white, fixedSize: const Size(48, 48)), icon: _sending ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded)),
          ])),
        ])),
      ),
    );
  }
}


// Shows a foreground in-app alert when a message arrives while Home is visible.
class HomeMessageNotifier extends StatefulWidget {
  const HomeMessageNotifier({super.key});
  @override
  State<HomeMessageNotifier> createState() => _HomeMessageNotifierState();
}

class _HomeMessageNotifierState extends State<HomeMessageNotifier> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  bool _firstSnapshot = true;
  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _subscription = FirebaseFirestore.instance.collection('private_chats').doc('private_chat').collection('messages').orderBy('createdAt', descending: true).limit(1).snapshots().listen((snapshot) {
      if (_firstSnapshot) { _firstSnapshot = false; return; }
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        if (change.type == DocumentChangeType.added && data['senderId'] != uid && mounted) {
          final content = (data['text'] as String?)?.trim();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(content == null || content.isEmpty ? 'New photo / location received ❤️' : 'New message: $content')));
          });
        }
      }
    }, onError: (_) {});
  }
  @override
  void dispose() { _subscription?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool showBadge;
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: color.withValues(alpha: 0.45))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(icon, size: 29, color: color),
                  ),
                  if (showBadge)
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 5),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: Icon(Icons.arrow_forward_rounded, size: 19, color: color)),
            ]),
          ),
        ),
      );
}

class RTechFooter extends StatelessWidget {
  const RTechFooter({super.key});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('POWERED BY', style: TextStyle(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.60) : Colors.black.withValues(alpha: 0.48))),
        const SizedBox(height: 6),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.all_inclusive_rounded, color: Color(0xFFFF65B8), size: 25),
          SizedBox(width: 7),
          Text('RTechnologies', style: TextStyle(color: Color(0xFFFF65B8), fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
      ]);
}

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  MobileAds.instance.initialize();
  runApp(LuminaWallsApp());
}

class LuminaWallsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina Walls',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF0B0F19),
        primaryColor: Color(0xFF00D2FF),
      ),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) return HomeScreen();
        return LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatelessWidget {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  void handleLogin(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wallpaper, size: 80, color: Color(0xFF00D2FF)),
            SizedBox(height: 16),
            Text("Lumina Walls Login", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            TextField(controller: emailController, decoration: InputDecoration(labelText: "Email")),
            TextField(controller: passwordController, decoration: InputDecoration(labelText: "Password"), obscureText: true),
            SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
              onPressed: () => handleLogin(context), 
              child: Text("Login"),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int changeCount = 0;
  bool isButtonEnabled = true;
  int secondsLeft = 0;
  Timer? _timer;
  InterstitialAd? _interstitialAd;
  String selectedCategory = "All";

  @override
  void initState() {
    super.initState();
    loadUserData();
    setupPushNotifications();
    loadInterstitialAd();
  }

  void setupPushNotifications() {
    FirebaseMessaging.instance.requestPermission();
  }

  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', 
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => print('Ad failed: $error'),
      ),
    );
  }

  void loadUserData() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    var doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      setState(() {
        changeCount = doc.data()?['change_count'] ?? 0;
      });
    }
  }

  void triggerWallpaperChange() async {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
      loadInterstitialAd();
    }

    String uid = FirebaseAuth.instance.currentUser!.uid;
    int randomDelay = Random().nextInt(3600) + 1; 

    setState(() {
      changeCount++;
      isButtonEnabled = false;
      secondsLeft = randomDelay;
    });

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'change_count': changeCount,
      'next_allowed_time': DateTime.now().add(Duration(seconds: randomDelay)),
    }, SetOptions(merge: true));

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (secondsLeft > 0) {
        setState(() { secondsLeft--; });
      } else {
        setState(() {
          isButtonEnabled = true;
          _timer?.cancel();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Lumina Walls", style: TextStyle(color: Color(0xFF00D2FF))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ["All", "AMOLED", "Sci-Fi", "Minimal", "Anime"].map((cat) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: selectedCategory == cat,
                    onSelected: (val) { setState(() { selectedCategory = cat; }); },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: selectedCategory == "All"
                  ? FirebaseFirestore.instance.collection('wallpapers').snapshots()
                  : FirebaseFirestore.instance.collection('wallpapers').where('category', isEqualTo: selectedCategory).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                var docs = snapshot.data!.docs;
                return GridView.builder(
                  padding: EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.7, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(data['url'], fit: BoxFit.cover),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(color: Color(0xFF131A26), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Total Wallpaper Changes: $changeCount", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                isButtonEnabled
                    ? ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF00D2FF), minimumSize: Size(double.infinity, 50)),
                        onPressed: triggerWallpaperChange,
                        child: Text("Instant Surprise Wallpaper", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      )
                    : Text("Next button unlocks in: $secondsLeft seconds", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }
}


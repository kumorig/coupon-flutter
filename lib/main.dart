import 'dart:io';

import 'package:contactus/contactus.dart';
import 'package:expansion_card/expansion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabbar/tabbar.dart';
import 'package:widget_circular_animator/widget_circular_animator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:let_log/let_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_apns/apns.dart';
import 'package:device_info/device_info.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const String API_URL = "https://inpact-coupon.azurewebsites.net/api";
// const String API_URL = "http://192.168.224.95:3001/api";
void main() {
  Logger.config.setPrintNames(log: "📮");
  Logger.log("App start");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'クーポン',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: MyHomePage(title: 'クーポン'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);
  final String title;

  @override
  _AppState createState() => _AppState();
}

Future<List<Blueprint>> fetchBlueprints() async {
  Logger.log("fetchBlueprints");
  final response = await http.get(API_URL + '/blueprints');
  if (response.statusCode == 200) {
    Iterable iter = json.decode(utf8.decode(response.bodyBytes));
    return List<Blueprint>.from(iter.map((bp) => Blueprint.fromJson(bp)));
  } else {
    throw Exception('Failed to load Blueprints');
  }
}

Future<dynamic> myBackgroundMessageHandler(Map<String, dynamic> message) async {
  Logger.log("got message!");
  if (message.containsKey('data')) {
    // Handle data message
    final dynamic data = message['data'];
  }

  if (message.containsKey('notification')) {
    // Handle notification message
    final dynamic notification = message['notification'];
    Logger.log('hmm $notification');
  }

  // Or do other work.
}

enum UseResponse { Yes, No }

// Widget couponListWidget() {
//   return
// }

class Blueprint {
  final int id;
  final String title;
  final String image;
  final String content;
  final String validFrom;
  final String validTo;
  final int useLimit;
  final bool isQr;
  final bool isButtonable;

  Blueprint(
      {this.id,
      this.title,
      this.image,
      this.content,
      this.validFrom,
      this.validTo,
      this.useLimit,
      this.isQr,
      this.isButtonable});

  factory Blueprint.fromJson(Map<String, dynamic> json) {
    return Blueprint(
      id: json['id'],
      title: json['title'],
      image: json['image'],
      content: json['content'],
      validFrom: json['valid_from'],
      validTo: json['valid_to'],
      useLimit: json['use_limit'],
    );
  }
}

class _AppState extends State<MyHomePage> {
  static final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final PushConnector connector = createPushConnector();
  final controller = PageController();
  final _formKey = GlobalKey<FormState>();
  String _email = "";
  String _name = "";
  Map<String, dynamic> _deviceData = <String, dynamic>{};
  bool isRegistered = false;
  List<Blueprint> futureBlueprints;

  @override
  void initState() {
    super.initState();
    _registerForPush();
    _checkRegistered();
    _initPlatformState().then((voidResult) {
      Logger.log("---", _deviceData);
    });
  }

  Future<void> _initPlatformState() async {
    Map<String, dynamic> deviceData = <String, dynamic>{};

    try {
      if (Platform.isAndroid) {
        deviceData = _readAndroidBuildData(await deviceInfoPlugin.androidInfo);
      } else if (Platform.isIOS) {
        deviceData = _readIosDeviceInfo(await deviceInfoPlugin.iosInfo);
      }
    } on PlatformException {
      deviceData = <String, dynamic>{
        'Error:': 'Failed to get platform version.'
      };
    }

    if (!mounted) return;

    setState(() {
      _deviceData = deviceData;
    });
  }

  Map<String, dynamic> _readAndroidBuildData(AndroidDeviceInfo build) {
    return <String, dynamic>{
      'version.securityPatch': build.version.securityPatch,
      'version.sdkInt': build.version.sdkInt,
      'version.release': build.version.release,
      'version.previewSdkInt': build.version.previewSdkInt,
      'version.incremental': build.version.incremental,
      'version.codename': build.version.codename,
      'version.baseOS': build.version.baseOS,
      'board': build.board,
      'bootloader': build.bootloader,
      'brand': build.brand,
      'device': build.device,
      'display': build.display,
      'fingerprint': build.fingerprint,
      'hardware': build.hardware,
      'host': build.host,
      'id': build.id,
      'manufacturer': build.manufacturer,
      'model': build.model,
      'product': build.product,
      'supported32BitAbis': build.supported32BitAbis,
      'supported64BitAbis': build.supported64BitAbis,
      'supportedAbis': build.supportedAbis,
      'tags': build.tags,
      'type': build.type,
      'isPhysicalDevice': build.isPhysicalDevice,
      'androidId': build.androidId,
      'systemFeatures': build.systemFeatures,
    };
  }

  Map<String, dynamic> _readIosDeviceInfo(IosDeviceInfo data) {
    return <String, dynamic>{
      'name': data.name,
      'systemName': data.systemName,
      'systemVersion': data.systemVersion,
      'model': data.model,
      'localizedModel': data.localizedModel,
      'identifierForVendor': data.identifierForVendor,
      'isPhysicalDevice': data.isPhysicalDevice,
      'utsname.sysname:': data.utsname.sysname,
      'utsname.nodename:': data.utsname.nodename,
      'utsname.release:': data.utsname.release,
      'utsname.version:': data.utsname.version,
      'utsname.machine:': data.utsname.machine,
    };
  }

  Future<void> _registerForPush() async {
    final connector = this.connector;
    connector.configure(
      onLaunch: (data) => onPush('onLaunch', data),
      onResume: (data) => onPush('onResume', data),
      onMessage: (data) => onPush('onMessage', data),
      onBackgroundMessage: myBackgroundMessageHandler,
    );

    connector.token.addListener(() {
      print('Token ${connector.token.value}');
    });
    connector.requestNotificationPermissions();

    if (connector is ApnsPushConnector) {
      connector.shouldPresent = (x) => Future.value(true);
    }
  }

  void _registerUser() async {
    var map = new Map<String, dynamic>();
    map['name'] = _name;
    map['role'] = "user";
    map['email'] = _email;
    map['device'] = json.encode(_deviceData);

    http.Response response = await http.post(API_URL + "/users",
        headers: {"Content-type": "application/json"},
        body: json.encode(map),
        encoding: Encoding.getByName("utf-8"));
    Logger.log("response.statusCode", response.statusCode);
    if (response.statusCode == 200) {
      String user = utf8.decode(response.body.runes.toList());
      _setRegistered(user);
    }
  }

  _setRegistered(String user) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isRegistered = true;
    });
    prefs.setBool('registered', true);
    prefs.setString('user', user);
    prefs.setString('device', json.encode(_deviceData));
  }

  _removeRegistered() {
    SharedPreferences.getInstance().then((SharedPreferences prefs) {
      setState(() {
        isRegistered = false;
      });
      prefs.setBool('registered', false);
    });
  }

  _checkRegistered() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isRegistered = prefs.getBool('registered') ?? false;
    });
  }

  Future<dynamic> onPush(String name, Map<String, dynamic> payload) {
    Logger.log('hmm: $name: $payload');

    final action = UNNotificationAction.getIdentifier(payload);

    if (action == 'MEETING_INVITATION') {
      // do something
    }

    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("インパクト クーポン"),
          centerTitle: true,
          bottom: PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: !isRegistered
                  ? SizedBox(height: 0.01) // nothing
                  : TabbarHeader(
                      controller: controller,
                      backgroundColor: Colors.white12,
                      tabs: [
                        Tab(text: "会社案内"),
                        Tab(text: "マイクーポン"),
                      ],
                    )),
        ),
        body: isRegistered
            ? tabContent(context)
            : pleaseRegisterContent(context));
  }

  pleaseRegisterContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
          key: _formKey,
          child: Center(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                decoration: const InputDecoration(
                  hintText: '名前',
                ),
                onSaved: (value) {
                  _name = value;
                },
                validator: (value) {
                  if (value.isEmpty) {
                    return '名前を入力してください。';
                  }
                  return null;
                },
              ),
              TextFormField(
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'メール',
                ),
                onSaved: (value) {
                  _email = value;
                },
                validator: (value) {
                  if (value.isEmpty) {
                    return 'メールアドレスを入力してください。';
                  }
                  return null;
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton(
                  onPressed: () {
                    // Validate will return true if the form is valid, or false if
                    // the form is invalid.
                    if (_formKey.currentState.validate()) {
                      _formKey.currentState.save();
                      _registerUser();
                    }
                  },
                  child: Text('登録'),
                ),
              ),
            ],
          ))),
    );
  }

  tabContent(BuildContext context) {
    return Center(
        child: TabbarContent(
      controller: controller,
      children: <Widget>[
        SingleChildScrollView(
          child: Container(
            color: Colors.white24,
            child: Column(
              children: [
                SizedBox(
                  height: 300,
                  child: WidgetCircularAnimator(
                    size: 200,
                    innerIconsSize: 3,
                    outerIconsSize: 3,
                    innerAnimation: Curves.bounceIn,
                    outerAnimation: Curves.bounceIn,
                    innerColor: Colors.orangeAccent,
                    reverse: false,
                    outerColor: Colors.orangeAccent,
                    innerAnimationSeconds: 20,
                    outerAnimationSeconds: 20,
                    child: Container(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child:
                            Image(image: AssetImage('assets/images/logo.png')),
                      ),
                    ),
                  ),
                ),
                Center(
                    child: ContactUs(
                        cardColor: Colors.white,
                        textColor: Colors.teal.shade900,
                        email: 'info@inpact.ne.jp',
                        emailText: 'info@inpact.ne.jp',
                        companyName: 'インパクト',
                        companyColor: Colors.teal.shade100,
                        phoneNumber: '099-210-5532',
                        phoneNumberText: '電話',
                        website: 'https://inpact.ne.jp',
                        websiteText: 'ウェッブサイト',
                        tagLine: '鹿児島WEBとシステム開発会社',
                        taglineColor: Colors.teal.shade100)),
                SizedBox.fromSize(size: Size(50, 50)),
                FlatButton(
                  color: Colors.red,
                  splashColor: Colors.black12,
                  onPressed: _removeRegistered,
                  child: Text("ユーザーを削除"),
                ),
              ],
            ),
          ),
        ),
        Container(
            color: Colors.black12,
            child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: FutureBuilder(
                  future: fetchBlueprints(),
                  builder: (context, AsyncSnapshot snapshot) {
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    } else {
                      return SingleChildScrollView(
                        child: Column(children: [
                          ListView.builder(
                              physics: ScrollPhysics(),
                              shrinkWrap: true,
                              itemCount: snapshot.data.length,
                              scrollDirection: Axis.vertical,
                              itemBuilder: (BuildContext context, int index) {
                                Blueprint blueprint = snapshot.data[index];
                                if (blueprint.useLimit < 1)
                                  return Padding(
                                      padding: const EdgeInsets.all(0.0));
                                else
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: ExpansionCard(
                                      margin: const EdgeInsets.all(20.0),
                                      borderRadius: 20,
                                      background: Image.asset(
                                        "assets/images/bg1.gif",
                                        fit: BoxFit.cover,
                                      ),
                                      title: Container(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              blueprint.title,
                                              style: TextStyle(
                                                fontSize: 30,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              blueprint.content,
                                              style: TextStyle(
                                                  fontSize: 20,
                                                  color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                      children: <Widget>[
                                        Container(
                                            margin: EdgeInsets.symmetric(
                                                horizontal: 7),
                                            color: Colors.white,
                                            child: SizedBox(
                                                height: 160,
                                                width: 160,
                                                child: QrImage(
                                                  data: API_URL +
                                                      "/coupon/" +
                                                      blueprint.id.toString(),
                                                  version: QrVersions.auto,
                                                  size: 200.0,
                                                ))),
                                        Container(
                                          margin: EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: FlatButton(
                                            minWidth: 200,
                                            padding: const EdgeInsets.all(16.0),
                                            color: Colors.blueGrey,
                                            textColor: Colors.white,
                                            splashColor: Colors.black12,
                                            onPressed: () async {
                                              switch (await showDialog<
                                                      UseResponse>(
                                                  context: context,
                                                  builder:
                                                      (BuildContext context) {
                                                    return SimpleDialog(
                                                      title: const Text(
                                                          'クーポン使用確認'),
                                                      children: <Widget>[
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(8.0),
                                                          child: Center(
                                                            child: Column(
                                                              children: [
                                                                Text(
                                                                    'クーポンが使用されようとしています。'),
                                                                Text(
                                                                    'このアクションを元に戻すことはできません。'),
                                                                Text(
                                                                    'クーポンを使用してもよろしいですか？'),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        SimpleDialogOption(
                                                          onPressed: () async {
                                                            var url = API_URL +
                                                                "/coupon/" +
                                                                blueprint.id
                                                                    .toString();
                                                            Logger.log(
                                                                "Using coupon..." +
                                                                    url);
                                                            await http.get(url);
                                                            setState(() {
                                                              snapshot.data
                                                                  .removeAt(0);
                                                            });
                                                            Navigator.pop(
                                                                context,
                                                                UseResponse
                                                                    .Yes);
                                                          },
                                                          child: const Text(
                                                              'クーポンを使う'),
                                                        ),
                                                        SimpleDialogOption(
                                                          onPressed: () {
                                                            Navigator.pop(
                                                                context,
                                                                UseResponse.No);
                                                          },
                                                          child: const Text(
                                                              'キャンセル'),
                                                        ),
                                                      ],
                                                    );
                                                  })) {
                                                case UseResponse.Yes:
                                                  // Let's go.
                                                  // ...
                                                  break;
                                                case UseResponse.No:
                                                  // ...
                                                  break;
                                              }
                                            },
                                            child: Text("クーポンを使う"),
                                          ),
                                        )
                                      ],
                                    ),
                                  );
                              })
                        ]),
                      );
                    }
                  },
                )))
      ],
    ));
  }
}

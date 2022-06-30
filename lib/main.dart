import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/foundation.dart' as Foundation;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.pink,
        backgroundColor: Colors.grey,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  late IO.Socket _socket;
  late RTCPeerConnection pc;
  final _localRenderer = RTCVideoRenderer();
  bool connected = false;
  late String serverHost;

  void requestAudio() {
    _socket.emit('message', {'type': 'ready'});
    debugPrint('requested audio');
  }

  void connect() {
    if (Foundation.kReleaseMode && serverHost.trim().isEmpty) {
      debugPrint('no server host');
      return;
    }

    var socketOptions = IO.OptionBuilder().setTransports(['websocket']).build();
    if (Foundation.kDebugMode) {
      if (Foundation.kIsWeb) {
        serverHost = 'http://localhost:3033';
      } else {
        // Android emulator
        serverHost = 'http://10.0.2.2:3033';
      }
    } else {
      _socket = IO.io(serverHost, socketOptions);
      debugPrint('connecting to $serverHost');
    }

    _socket.onConnect((_) {
      debugPrint('connected to server');
    });

    _socket.onDisconnect((_) => debugPrint('disconnected'));

    _socket.on("message", (data) async {
      var payload = data["payload"];

      if (data["type"] == "offer") {
        var sdp = RTCSessionDescription(payload['sdp'], payload['type']);
        handleOffer(sdp);
      } else if (data['type'] == 'candidate') {
        var candidate = RTCIceCandidate(
            payload['candidate'], payload['sdpMid'], payload['sdpMLineIndex']);
        handleCandidate(candidate);
      }
    });
  }

  void handleConnect() {
    requestAudio();

    setState(() {
      connected = true;
    });
  }

  void disconnect() {
    _localRenderer.srcObject = null;
    pc.close();

    setState(() {
      connected = false;
    });
  }

  void handleOffer(offer) async {
    debugPrint('handle offer');
    pc = await createPeerConnection({});

    pc.onAddStream = (stream) {
      debugPrint('received stream $stream');
      _localRenderer.srcObject = stream;

      setState(() {
        connected = true;
      });
    };

    pc.onIceCandidate = (candidate) {
      _socket.emit('message', {
        'type': 'candidate',
        'payload': candidate.toMap(),
      });
    };

    pc.onConnectionState = (state) {
      debugPrint('connection state $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          connected = true;
        });
      }
    };

    await pc.setRemoteDescription(offer);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    _socket.emit("message", {'type': 'answer', 'payload': answer.toMap()});
  }

  void handleCandidate(candidate) async {
    try {
      await pc.addCandidate(candidate);
    } catch (e) {}
  }

  void initRenderers() async {
    await _localRenderer.initialize();
  }

  @override
  void initState() {
    super.initState();
    initRenderers();
    connect();
  }

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have daaa the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
            ElevatedButton(
              onPressed: connected ? disconnect : handleConnect,
              child: Text(connected ? 'Disconnect' : 'Connect'),
            ),
            Text(connected ? 'Playing' : 'Not Playing'),
            //  Server host text input
            TextField(
              decoration: const InputDecoration(
                labelText: 'Server Host',
              ),
              onChanged: (text) {
                serverHost = text;
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

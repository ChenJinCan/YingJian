import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/presentation/prototype/mvp_flow_prototype_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  runApp(const MvpFlowPrototypeApp());
}

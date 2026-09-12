import 'package:flutter_ai_agent/data/datasources/tools/chat/contact_launcher_platform_wrapper.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;
final sl = getIt;

@InjectableInit()
void configureInjection() {
  getIt.init();
  ContactsPlatformWrapperRegistry.instance ??= DefaultContactsPlatformWrapper();
}

Future<void> initDependencies() async => configureInjection();

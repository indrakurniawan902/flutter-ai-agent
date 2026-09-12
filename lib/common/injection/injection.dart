import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;
final sl = getIt;

@InjectableInit()
void configureInjection() => getIt.init();

Future<void> initDependencies() async => configureInjection();

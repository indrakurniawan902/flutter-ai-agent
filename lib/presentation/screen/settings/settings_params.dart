import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';

class SettingsParams {
  final SettingsCubit? cubit;
  final ServerProfileCubit? serverProfileCubit;

  const SettingsParams({
    this.cubit,
    this.serverProfileCubit,
  });
}

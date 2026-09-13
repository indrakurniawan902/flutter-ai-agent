import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';

class DefaultSystemSettingsPlatformWrapper
    implements SystemSettingsPlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/intent_settings');

  @override
  Future<bool> openSystemSettings(String settingType) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openSystemSettings',
            <String, dynamic>{'type': settingType},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

@LazySingleton(as: IntentLauncherServiceBase)
class IntentLauncherServiceImpl implements IntentLauncherServiceBase {
  static const Set<String> _allowedSettings = {
    'bluetooth',
    'wifi',
    'battery_saver',
    'airplane_mode',
    'location',
    'display',
    'sound',
    'apps',
    'nfc',
  };

  final UrlLauncherProvider _launcher;
  final SystemSettingsPlatformWrapper _settingsWrapper;

  IntentLauncherServiceImpl({
    UrlLauncherProvider? launcher,
    SystemSettingsPlatformWrapper? settingsWrapper,
  })  : _launcher = launcher ?? DefaultUrlLauncherProvider(),
        _settingsWrapper = settingsWrapper ??
            (SystemSettingsPlatformWrapperRegistry.instance ??
                DefaultSystemSettingsPlatformWrapper());

  @factoryMethod
  factory IntentLauncherServiceImpl.create() => IntentLauncherServiceImpl();

  @override
  Future<Either<Failure, String>> openWhatsappChat(
    String phoneNumber, {
    String? message,
  }) async {
    try {
      final digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isEmpty) {
        return const Left(ServerFailure('Invalid phone number'));
      }
      final queryParameters = (message != null && message.isNotEmpty)
          ? <String, String>{'text': message}
          : null;
      final uri = Uri(
        scheme: 'https',
        host: 'wa.me',
        path: digits,
        queryParameters: queryParameters,
      );
      final canLaunch = await _launcher.canLaunchUrl(uri);
      if (!canLaunch) {
        return const Left(
          ServerFailure('No app available to handle WhatsApp on this device'),
        );
      }
      final launched = await _launcher.launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Left(ServerFailure('Failed to open WhatsApp for $phoneNumber'));
      }
      return Right('WhatsApp chat opened for $phoneNumber');
    } catch (e) {
      return Left(ServerFailure('Error opening WhatsApp: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> openMapNavigation({
    double? latitude,
    double? longitude,
    String? query,
  }) async {
    try {
      final String label;
      final String queryValue;
      final Uri geoUri;
      if (latitude != null && longitude != null) {
        final coords = '$latitude,$longitude';
        label = coords;
        queryValue = coords;
        geoUri = Uri(
          scheme: 'geo',
          path: coords,
          queryParameters: <String, String>{'q': coords},
        );
      } else if (query != null && query.isNotEmpty) {
        label = 'query "$query"';
        queryValue = query;
        geoUri = Uri(
          scheme: 'geo',
          path: '0,0',
          queryParameters: <String, String>{'q': query},
        );
      } else {
        return const Left(
          ServerFailure('Provide coordinates or a query for map navigation'),
        );
      }

      final canGeo = await _launcher.canLaunchUrl(geoUri);
      if (canGeo) {
        final launched = await _launcher.launchUrl(
          geoUri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          return Left(ServerFailure('Failed to open map navigation'));
        }
        return Right('Opened map navigation for $label');
      }

      final fallback = Uri(
        scheme: 'https',
        host: 'www.google.com',
        path: '/maps/search',
        queryParameters: <String, String>{
          'api': '1',
          'query': queryValue,
        },
      );
      final canFallback = await _launcher.canLaunchUrl(fallback);
      if (!canFallback) {
        return const Left(
          ServerFailure('No app available to handle map navigation'),
        );
      }
      final launched = await _launcher.launchUrl(
        fallback,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Left(ServerFailure('Failed to open map navigation'));
      }
      return Right('Opened map navigation for $label');
    } catch (e) {
      return Left(ServerFailure('Error opening map navigation: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> openEmailComposer({
    String? to,
    String? subject,
    String? body,
  }) async {
    try {
      final hasTo = to != null && to.isNotEmpty;
      final hasSubject = subject != null && subject.isNotEmpty;
      final hasBody = body != null && body.isNotEmpty;
      if (!hasTo && !hasSubject && !hasBody) {
        return const Left(ServerFailure('Nothing to compose'));
      }

      final queryParameters = <String, String>{
        if (hasSubject) 'subject': subject,
        if (hasBody) 'body': body,
      };
      final uri = Uri(
        scheme: 'mailto',
        path: to ?? '',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

      final canLaunch = await _launcher.canLaunchUrl(uri);
      if (!canLaunch) {
        return const Left(
          ServerFailure('No app available to handle email on this device'),
        );
      }
      final launched = await _launcher.launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return const Left(ServerFailure('Failed to open email composer'));
      }
      return const Right('Email composer opened');
    } catch (e) {
      return Left(ServerFailure('Error opening email composer: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> launchSystemSetting(String settingType) async {
    try {
      final normalized = settingType.trim().toLowerCase();
      if (!_allowedSettings.contains(normalized)) {
        return Left(ServerFailure('Unknown setting type: $settingType'));
      }
      final opened = await _settingsWrapper.openSystemSettings(normalized);
      if (!opened) {
        return Left(ServerFailure('Failed to open $normalized settings'));
      }
      return Right('Opened $normalized settings');
    } catch (e) {
      return Left(ServerFailure('Error opening system settings: $e'));
    }
  }
}

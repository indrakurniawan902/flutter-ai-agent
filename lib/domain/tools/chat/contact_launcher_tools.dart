import 'dart:convert';

import 'package:contacts_service/contacts_service.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';

abstract class ContactsPlatformWrapper {
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
}

class ContactsPlatformWrapperRegistry {
  static ContactsPlatformWrapper? instance;
}

abstract class ContactsProvider {
  Future<bool> checkPermission();
  Future<List<Map<String, dynamic>>> searchContacts(String query);
}

class DefaultContactsProvider implements ContactsProvider {
  final ContactsPlatformWrapper? _platformWrapper;

  DefaultContactsProvider({ContactsPlatformWrapper? platformWrapper})
      : _platformWrapper = platformWrapper;

  @override
  Future<bool> checkPermission() async {
    final wrapper = _platformWrapper ?? ContactsPlatformWrapperRegistry.instance;
    if (wrapper != null) {
      try {
        final isGranted = await wrapper.isPermissionGranted();
        if (isGranted) return true;
        return await wrapper.requestPermission();
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<List<Map<String, dynamic>>> searchContacts(String query) async {
    try {
      final contacts = await ContactsService.getContacts(query: query);
      return contacts
          .map((c) => {
                'displayName': c.displayName ?? '',
                'phones': c.phones
                        ?.map((p) => p.value)
                        .whereType<String>()
                        .toList() ??
                    <String>[],
                'emails': c.emails
                        ?.map((e) => e.value)
                        .whereType<String>()
                        .toList() ??
                    <String>[],
              })
          .toList();
    } catch (_) {
      return [];
    }
  }
}

abstract class UrlLauncherProvider {
  Future<bool> canLaunchUrl(Uri url);
  Future<bool> launchUrl(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  });
}

class DefaultUrlLauncherProvider implements UrlLauncherProvider {
  @override
  Future<bool> canLaunchUrl(Uri url) => url_launcher.canLaunchUrl(url);

  @override
  Future<bool> launchUrl(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) =>
      url_launcher.launchUrl(url, mode: mode);
}

@lazySingleton
class ContactLauncherTools {
  final ContactsProvider _contactsProvider;
  final UrlLauncherProvider _urlLauncherProvider;

  ContactLauncherTools({
    ContactsProvider? contactsProvider,
    UrlLauncherProvider? urlLauncherProvider,
  })  : _contactsProvider = contactsProvider ?? DefaultContactsProvider(),
        _urlLauncherProvider =
            urlLauncherProvider ?? DefaultUrlLauncherProvider();

  Future<bool> checkContactsPermission() => _contactsProvider.checkPermission();

  Future<Either<Failure, String>> searchContacts(String query) async {
    try {
      final contacts = await _contactsProvider.searchContacts(query);
      return Right(jsonEncode(contacts));
    } catch (e) {
      return Left(ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to search contacts')));
    }
  }

  Future<Either<Failure, String>> openWhatsappChat(
    String phone, {
    String? message,
  }) async {
    try {
      final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isEmpty) {
        return const Left(ServerFailure('Invalid phone number'));
      }
      final String urlString;
      if (message != null && message.isNotEmpty) {
        urlString =
            'https://wa.me/$digits?text=${Uri.encodeComponent(message)}';
      } else {
        urlString = 'https://wa.me/$digits';
      }
      final uri = Uri.parse(urlString);
      final canLaunch = await _urlLauncherProvider.canLaunchUrl(uri);
      if (!canLaunch) {
        return const Left(
          ServerFailure(
            'No app available to handle WhatsApp on this device',
          ),
        );
      }
      final launched = await _urlLauncherProvider.launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Left(ServerFailure('Failed to open WhatsApp for $phone'));
      }
      return Right('WhatsApp chat opened for $phone');
    } catch (e) {
      return Left(ServerFailure(
          FailureMessage.humanize(e, context: 'Error opening WhatsApp')));
    }
  }

  Future<Either<Failure, String>> openExternalUrl(String url) async {
    try {
      final trimmed = url.trim();
      final uri = Uri.tryParse(trimmed);
      if (uri == null ||
          (!uri.isScheme('http') && !uri.isScheme('https')) ||
          uri.host.isEmpty) {
        return Left(ServerFailure('Invalid URL: $url'));
      }
      final canLaunch = await _urlLauncherProvider.canLaunchUrl(uri);
      if (!canLaunch) {
        return Left(ServerFailure('Cannot launch URL: $url'));
      }
      final launched = await _urlLauncherProvider.launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Left(ServerFailure('Failed to launch URL: $url'));
      }
      return Right('Opened URL: $url');
    } catch (e) {
      return Left(ServerFailure(
          FailureMessage.humanize(e, context: 'Error launching URL')));
    }
  }

  Future<Either<Failure, String>> openPhoneCall(String phone) async {
    try {
      final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isEmpty) {
        return const Left(ServerFailure('Invalid phone number'));
      }
      final uri = Uri(scheme: 'tel', path: digits);
      final canLaunch = await _urlLauncherProvider.canLaunchUrl(uri);
      if (!canLaunch) {
        return const Left(
          ServerFailure('No app available to handle phone calls on this device'),
        );
      }
      final launched = await _urlLauncherProvider.launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return Left(ServerFailure('Failed to open the dialer for $phone'));
      }
      return Right('Phone dialer opened for $phone');
    } catch (e) {
      return Left(ServerFailure(
          FailureMessage.humanize(e, context: 'Error opening phone dialer')));
    }
  }
}

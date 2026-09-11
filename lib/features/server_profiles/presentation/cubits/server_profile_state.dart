import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';

/// Base state for [ServerProfileCubit].
sealed class ServerProfileState extends Equatable {
  final List<ServerProfile> profiles;
  final ServerProfile? activeProfile;

  const ServerProfileState({
    this.profiles = const [],
    this.activeProfile,
  });

  @override
  List<Object?> get props => [profiles, activeProfile];
}

/// Initial state before profiles are loaded.
class ServerProfileInitial extends ServerProfileState {
  const ServerProfileInitial({
    super.profiles,
    super.activeProfile,
  });
}

/// Loading server profiles or performing asynchronous storage operation.
class ServerProfileLoading extends ServerProfileState {
  const ServerProfileLoading({
    super.profiles,
    super.activeProfile,
  });
}

/// Server profiles successfully loaded.
class ServerProfileLoaded extends ServerProfileState {
  const ServerProfileLoaded({
    required super.profiles,
    super.activeProfile,
  });
}

/// Server profile operation (add, delete, switch) succeeded.
class ServerProfileOperationSuccess extends ServerProfileState {
  final String message;

  const ServerProfileOperationSuccess({
    required super.profiles,
    super.activeProfile,
    required this.message,
  });

  @override
  List<Object?> get props => [profiles, activeProfile, message];
}

/// An error occurred during validation, loading, or saving of server profiles.
class ServerProfileError extends ServerProfileState {
  final String message;

  const ServerProfileError({
    super.profiles,
    super.activeProfile,
    required this.message,
  });

  @override
  List<Object?> get props => [profiles, activeProfile, message];
}

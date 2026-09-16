import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure([super.message = 'Server error occurred', this.statusCode]);

  @override
  List<Object> get props => [message, statusCode ?? -1];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network error occurred']);
}

class ConnectionFailure extends Failure {
  const ConnectionFailure([super.message = 'Connection failed']);
}

class ParseFailure extends Failure {
  const ParseFailure([super.message = 'Parse error occurred']);
}

class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Storage error occurred']);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'Permission denied']);
}

class UnsupportedEndpointFailure extends Failure {
  const UnsupportedEndpointFailure([
    super.message = 'Endpoint not supported by the active server',
  ]);
}

class ListenerNotConnectedFailure extends Failure {
  const ListenerNotConnectedFailure([
    super.message =
        'Notification listener service is not connected [listener_not_connected]',
  ]);
}

class CameraCancelledFailure extends Failure {
  const CameraCancelledFailure([
    super.message = 'camera_cancelled: User cancelled image capture',
  ]);
}

class CameraLostResultFailure extends Failure {
  const CameraLostResultFailure([
    super.message = 'camera_lost_result: Camera result lost to Activity recreation',
  ]);
}

class CameraBusyFailure extends Failure {
  const CameraBusyFailure([
    super.message = 'camera_busy: Image picker is already active',
  ]);
}

class CameraTimeoutFailure extends Failure {
  const CameraTimeoutFailure([
    super.message = 'camera_timeout: Image capture timed out',
  ]);
}

class VoiceTurnBusyFailure extends Failure {
  const VoiceTurnBusyFailure([
    super.message = 'voice_turn_busy: a voice turn is already in progress',
  ]);
}

class VoiceTurnEmptyFailure extends Failure {
  const VoiceTurnEmptyFailure([
    super.message = 'voice_turn_empty: no speech was recognized',
  ]);
}

class VoiceTurnNoTransportFailure extends Failure {
  const VoiceTurnNoTransportFailure([
    super.message = 'voice_turn_no_transport: no chat transport is available',
  ]);
}

class VoiceTurnNeedsApprovalFailure extends Failure {
  const VoiceTurnNeedsApprovalFailure([
    super.message =
        'voice_turn_needs_approval: the agent is waiting for action approval',
  ]);
}

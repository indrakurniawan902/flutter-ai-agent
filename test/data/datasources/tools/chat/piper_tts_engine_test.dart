import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/piper_tts_engine.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlayer extends Mock implements AudioPlayerWrapper {}

class _FakeSherpa implements SherpaTtsWrapper {
  Float32List samples = Float32List(0);
  int sampleRate = 16000;
  int calls = 0;

  @override
  void ensureBindings() {}

  @override
  GeneratedAudioData synthesize({
    required String modelPath,
    required String tokensPath,
    required String dataDirPath,
    required String text,
    int sid = 0,
    double speed = 1.0,
  }) {
    calls++;
    return GeneratedAudioData(samples: samples, sampleRate: sampleRate);
  }
}

class _FakeStore implements PiperVoiceStoreBase {
  _FakeStore(this.root);

  final String root;
  final Map<String, bool> readiness = {};

  @override
  String modelDirFor(String voiceId) =>
      '$root${Platform.pathSeparator}$voiceId';

  @override
  Future<bool> isVoiceReady(String voiceId) async =>
      readiness[voiceId] ?? false;

  @override
  Future<void> downloadVoice(
    PiperVoiceDescriptor voice, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<void> deleteVoice(String voiceId) async {}
}

void main() {
  late _MockPlayer player;
  late _FakeSherpa sherpa;
  late _FakeStore store;
  late PiperTtsEngine engine;

  setUpAll(() {
    registerFallbackValue(BytesSource(Uint8List(0)));
  });

  setUp(() {
    player = _MockPlayer();
    sherpa = _FakeSherpa();
    store = _FakeStore('models');
    when(
      () => player.onPlayerStateChanged,
    ).thenAnswer((_) => Stream.value(PlayerState.completed));
    when(() => player.play(any())).thenAnswer((_) async {});
    when(() => player.stop()).thenAnswer((_) async {});
    when(() => player.setVolume(any())).thenAnswer((_) async {});
    engine = PiperTtsEngine(
      store: store,
      sherpa: sherpa,
      player: player,
      nativeSupported: () => true,
    );
  });

  group('PiperTtsEngine.prepare', () {
    test('returns false when store reports not ready', () async {
      expect(await engine.prepare('v1'), isFalse);
      expect(engine.activeVoiceId, isNull);
    });

    test('returns true and records voice when ready', () async {
      store.readiness['v1'] = true;

      expect(await engine.prepare('v1'), isTrue);
      expect(engine.activeVoiceId, 'v1');
    });
  });

  group('PiperTtsEngine.speak', () {
    test('returns false without touching native when unsupported', () async {
      store.readiness['v1'] = true;
      final offline = PiperTtsEngine(
        store: store,
        sherpa: sherpa,
        player: player,
        nativeSupported: () => false,
      );

      expect(await offline.prepare('v1'), isTrue);
      expect(await offline.speak('hello'), isFalse);
      verifyNever(() => player.play(any()));
      expect(sherpa.calls, 0);
    });

    test('synthesizes, plays WAV bytes, completes', () async {
      store.readiness['v1'] = true;
      sherpa.samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0]);
      sherpa.sampleRate = 16000;

      expect(await engine.prepare('v1'), isTrue);
      expect(await engine.speak('hello'), isTrue);

      final captured = verify(() => player.play(captureAny())).captured;
      expect(captured, hasLength(1));
      final source = captured.single as BytesSource;
      expect(String.fromCharCodes(source.bytes.sublist(0, 4)), 'RIFF');
      expect(source.bytes.length, 44 + 4 * 2);
    });

    test('returns false when synthesis yields no samples', () async {
      store.readiness['v1'] = true;
      sherpa.samples = Float32List(0);

      expect(await engine.prepare('v1'), isTrue);
      expect(await engine.speak('hello'), isFalse);
      verifyNever(() => player.play(any()));
    });
  });

  group('PiperTtsEngine.stop', () {
    test('delegates to player and swallows errors', () async {
      when(() => player.stop()).thenThrow(Exception('boom'));

      await expectLater(engine.stop(), completes);
      verify(() => player.stop()).called(1);
    });
  });

  group('PiperVoiceStore readiness probes', () {
    test('isVoiceReady follows injected file/dir probes', () async {
      final ready = PiperVoiceStore(
        rootDirPath: () => '/models',
        fileExists: (_) => true,
        dirExists: (_) => true,
      );
      expect(await ready.isVoiceReady('any_voice'), isTrue);

      final missingModel = PiperVoiceStore(
        rootDirPath: () => '/models',
        fileExists: (_) => false,
        dirExists: (_) => true,
      );
      expect(await missingModel.isVoiceReady('any_voice'), isFalse);

      final missingData = PiperVoiceStore(
        rootDirPath: () => '/models',
        fileExists: (_) => true,
        dirExists: (_) => false,
      );
      expect(await missingData.isVoiceReady('any_voice'), isFalse);
    });

    test('modelDirFor joins voice id under the injected root', () {
      final probe = PiperVoiceStore(rootDirPath: () => '/models');

      expect(probe.modelDirFor('v1'), '/models${Platform.pathSeparator}v1');
    });
  });

  group('PiperVoiceStore.downloadVoice', () {
    const voiceId = 'test_voice-medium';
    late Directory tmp;
    late Uint8List tarball;
    late String tarballMd5;

    String join(String first, String second) =>
        '$first${Platform.pathSeparator}$second';

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('piper_store');
      final onnx = Uint8List.fromList(List<int>.generate(256, (i) => i % 256));
      final tokens = Uint8List.fromList('a b c\n'.codeUnits);
      final data = Uint8List.fromList([1, 2, 3, 4]);
      const prefix = 'vits-piper-$voiceId';
      final archive = Archive()
        ..addFile(ArchiveFile('$prefix/$voiceId.onnx', onnx.length, onnx))
        ..addFile(ArchiveFile('$prefix/tokens.txt', tokens.length, tokens))
        ..addFile(ArchiveFile('$prefix/espeak-ng-data/x', data.length, data));
      final tarBytes = TarEncoder().encode(archive);
      tarball = Uint8List.fromList(BZip2Encoder().encode(tarBytes));
      tarballMd5 = md5.convert(tarball).toString();
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    PiperVoiceDescriptor descriptor(String md5Hex) => PiperVoiceDescriptor(
      id: voiceId,
      label: 'Test voice',
      language: 'en',
      modelFileName: '$voiceId.onnx',
      tarballName: 'vits-piper-$voiceId.tar.bz2',
      tarballMd5: md5Hex,
      tarballSizeBytes: tarball.length,
      downloadUrl: 'https://example.invalid/x.tar.bz2',
    );

    test('extracts model files and removes the tmp tarball', () async {
      final voice = descriptor(tarballMd5);
      final probe = PiperVoiceStore(
        rootDirPath: () => tmp.path,
        fetchBytes: (url, progress) async => tarball,
      );

      await probe.downloadVoice(voice);

      final dir = join(tmp.path, voiceId);
      expect(File(join(dir, '$voiceId.onnx')).existsSync(), isTrue);
      expect(File(join(dir, 'tokens.txt')).existsSync(), isTrue);
      expect(File(join(join(dir, 'espeak-ng-data'), 'x')).existsSync(), isTrue);
      expect(
        File(join(join(tmp.path, 'tmp'), voice.tarballName)).existsSync(),
        isFalse,
      );
      expect(await probe.isVoiceReady(voiceId), isTrue);
    });

    test('throws integrity error and deletes tmp on md5 mismatch', () async {
      final voice = descriptor('0' * 32);
      final probe = PiperVoiceStore(
        rootDirPath: () => tmp.path,
        fetchBytes: (url, progress) async => tarball,
      );

      await expectLater(
        () => probe.downloadVoice(voice),
        throwsA(isA<VoiceModelIntegrityException>()),
      );
      expect(
        File(join(join(tmp.path, 'tmp'), voice.tarballName)).existsSync(),
        isFalse,
      );
    });
  });
}

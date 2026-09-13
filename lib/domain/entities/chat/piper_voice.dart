/// Catalog descriptor for a downloadable Piper (sherpa-onnx vits)
/// voice model.
class PiperVoiceDescriptor {
  final String id;
  final String label;
  final String language;
  final String modelFileName;
  final String tarballName;
  final String tarballMd5;
  final int tarballSizeBytes;
  final String downloadUrl;

  const PiperVoiceDescriptor({
    required this.id,
    required this.label,
    required this.language,
    required this.modelFileName,
    required this.tarballName,
    required this.tarballMd5,
    required this.tarballSizeBytes,
    required this.downloadUrl,
  });
}

/// The release tarball layout is: `vits-piper-<id>/` containing
/// `<id>.onnx`, `tokens.txt` and `espeak-ng-data/`.
const List<PiperVoiceDescriptor> kPiperVoiceCatalog = [
  PiperVoiceDescriptor(
    id: 'id_ID-news_tts-medium',
    label: 'Bahasa Indonesia — news_tts',
    language: 'id_ID',
    modelFileName: 'id_ID-news_tts-medium.onnx',
    tarballName: 'vits-piper-id_ID-news_tts-medium.tar.bz2',
    tarballMd5: 'c91a63c2fa185b6f54609019e19232ef',
    tarballSizeBytes: 67243848,
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-id_ID-news_tts-medium.tar.bz2',
  ),
  PiperVoiceDescriptor(
    id: 'en_US-lessac-medium',
    label: 'English (US) — lessac',
    language: 'en_US',
    modelFileName: 'en_US-lessac-medium.onnx',
    tarballName: 'vits-piper-en_US-lessac-medium.tar.bz2',
    tarballMd5: 'e7e26d0730b3cb9b451efb3f7f700daf',
    tarballSizeBytes: 67230653,
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
  ),
  PiperVoiceDescriptor(
    id: 'en_GB-alba-medium',
    label: 'English (GB) — alba',
    language: 'en_GB',
    modelFileName: 'en_GB-alba-medium.onnx',
    tarballName: 'vits-piper-en_GB-alba-medium.tar.bz2',
    tarballMd5: 'a1cf0566103318225da2f3e58ed0f2d2',
    tarballSizeBytes: 67212349,
    downloadUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2',
  ),
];

PiperVoiceDescriptor? piperVoiceById(String id) {
  for (final voice in kPiperVoiceCatalog) {
    if (voice.id == id) return voice;
  }
  return null;
}

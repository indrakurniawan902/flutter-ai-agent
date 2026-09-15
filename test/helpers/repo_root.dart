import 'dart:io';

bool _hasRepoMarker(Directory dir) =>
    File('${dir.path}/pubspec.yaml').existsSync() &&
    Directory('${dir.path}/lib').existsSync();

Directory? _walkUpToMarker(String path) {
  var dir = Directory(path).absolute;
  while (true) {
    if (_hasRepoMarker(dir)) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Resolves the repository root without trusting the process working directory.
///
/// Candidates are tried in order: the test script's own location, then
/// [Directory.current] as a last resort. A candidate is accepted only when it
/// contains both `pubspec.yaml` and `lib/`, and the walk goes upward from the
/// candidate so a file path is fine.
///
/// Throws a [StateError] when no candidate carries the marker: a wrongly-rooted
/// run must fail loudly instead of silently skipping its assertions.
Directory resolveRepoRoot() {
  final candidates = <String>[
    Platform.script.toFilePath(),
    Directory.current.path,
  ];

  for (final candidate in candidates) {
    final resolved = _walkUpToMarker(candidate);
    if (resolved != null) return resolved;
  }

  throw StateError(
    'repo root not found: no ancestor of the script path or the working '
    'directory contains both pubspec.yaml and lib/',
  );
}

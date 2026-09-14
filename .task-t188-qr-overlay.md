[TASK ASSIGNMENT]
Task ID: T18.8-A (QR scanner viewfinder overlay fix)
Repo: /home/ubuntu/projects/flutter-ai-agent (branch: development, working tree has unrelated WIP in other files — do NOT touch anything outside Target Files)

Target Files:
- lib/presentation/screen/pairing/qr_scanner_screen.dart (MODIFY — only the `_ViewfinderOverlay` widget and the app bar header padding)
- test/presentation/screen/pairing/qr_scanner_screen_test.dart (MODIFY — add overlay painting tests)

Files to NOT Touch:
- Any file outside the two targets above. The working tree contains unrelated staged/unstaged WIP (chat_screen, voice_output_service, tool_registry, etc.) — leave every other file byte-identical.

Context & Architectural Rules:
- The screen currently renders `_ViewfinderOverlay` with a `ColorFiltered` + `BlendMode.srcOut`/`dstOut` stack (lines ~287-371). On real devices this composites to a SOLID OPAQUE WHITE BLOCK over the camera preview (the white rounded rect used for the cutout punch-through paints as white instead of punching a hole) and NO dark scrim outside the frame. This is the bug.
- Replace the entire `_ViewfinderOverlay` implementation with a `CustomPainter`-based scrim: single `CustomPaint` filling the overlay; in `paint()`, fill the full canvas with `Colors.black.withValues(alpha: 0.65)`, then punch the cutout using `Path.combine(PathOperation.difference, outerPath, cutoutRRect)` and fill the resulting path. The cutout is a 250x250 rounded rect (radius 16) centered horizontally, `top = (screenHeight - 250) / 2 - 40`. This is the standard, deterministic approach — the current blend-mode stack is fragile across devices.
- Frame border: keep the existing teal `#008080` 2.0 border with radius 16 (draw it in the same painter or keep the Positioned container — your choice, but design tokens are fixed: `#008080` teal, `#0F172A` dark surface, radius 16).
- Corner accents: draw 4 short teal corner brackets (e.g. 24px legs, 3px stroke) at the cutout corners in the same painter for scannability.
- Instruction text "Align QR code within the frame": wrap it in a scrim-backed container — a dark pill (`Colors.black.withValues(alpha: 0.55)`, radius 20, padding h16 v8) positioned below the frame (top = cutout bottom + 24), so it stays legible over a bright camera feed. Keep the same text string (tests assert it).
- Header padding: the app bar currently uses default AppBar `actions` padding; make the flash toggle's right edge padding visually equal to the back arrow's left edge padding (e.g. wrap the torch IconButton in a `Padding(padding: EdgeInsets.only(right: 8))` or use a leading-width-consistent approach — smallest change that achieves symmetric visual edge spacing).
- Keep ALL existing behavior intact: torch toggle wiring, manual input button, back navigation, `scannerWidgetBuilder` hook, and the scanner lifecycle (controller disposal rules unchanged). Do NOT touch `QrScannerController` or any domain/data code.
- Design tokens only: no new colors beyond `#008080` teal, `#0F172A`, `#334155`, `Colors.black`/`Colors.white` with alpha. Zero emoji icons.

Widget tests to ADD in test/presentation/screen/pairing/qr_scanner_screen_test.dart (new group `QrScannerScreen - Viewfinder Overlay Painting`):
1. Cutout transparency: pump the screen with `scannerWidgetBuilder` returning a bright opaque container (e.g. red `Colors.red` 250x250 sized at the cutout location); assert the pixel inside the cutout center is fully opaque red (no scrim tint). Use `tester.binding.runAsync` + `RepaintBoundary` capture (`captureImage` via `tester.binding`... simplest: wrap test app in a RepaintBoundary, `await expectLater(find.byType(RepaintBoundary), matchesGoldenFile(...))` is overkill — instead use `tester.widget`-level asserts where possible and pixel test via `captureImage` from `package:flutter_test/flutter_test.dart`).
2. Scrim outside: same setup; assert pixels sampled near the screen corners are darkened toward black (red channel significantly lower than 255).
3. Corner bracket presence: assert the CustomPaint exists inside the overlay Key('qr_viewfinder_overlay') and the painter is of your new painter type.
Keep the existing tests passing untouched (they only assert keys/text presence).

Note on pixel tests: default test surface is 800x600; the cutout is positioned `top = (600-250)/2 - 40 = 130`, centered horizontally (`left = 275`). Sample: cutout center ≈ (400, 255); a corner sample ≈ (10, 10). Colors.white text pill is below the frame; avoid sampling it.

Definition of Done (DoD):
- Run: flutter analyze  (exit 0, no new issues)
- Run: flutter test test/presentation/screen/pairing/qr_scanner_screen_test.dart  (100% pass)
- Run: sh tool/check_layout.sh  (prints LAYOUT OK)
- Run: git status --short and confirm ONLY the two target files changed.
- Report the actual tail output of each command in your final summary. Do not fabricate results.

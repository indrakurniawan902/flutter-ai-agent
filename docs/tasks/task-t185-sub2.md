# Task T18.5 Sub-task 2: AndroidManifest launchMode & taskAffinity fix for image_picker

## Target File (ONLY this file)
- `android/app/src/main/AndroidManifest.xml`

## Context & Rules
- `android:launchMode="singleTask"` and `android:taskAffinity=""` cause external camera Intent round-trips on Android (especially Android 14 / MIUI / HyperOS) to detach or recreate MainActivity without delivering the camera result.
- Official image_picker and Flutter documentation requires `android:launchMode="singleTop"` and default task affinity (remove `android:taskAffinity=""`).
- `singleTop` maintains full compatibility with share targets (SEND / SEND_MULTIPLE) and deep link VIEW intents via `onNewIntent`.

## Goal
In `android/app/src/main/AndroidManifest.xml`, update the `.MainActivity` `<activity>` tag:
1. Change `android:launchMode="singleTask"` to `android:launchMode="singleTop"`.
2. Remove `android:taskAffinity=""`.

## Definition of Done (DoD)
- Verify `android/app/src/main/AndroidManifest.xml` contains `android:launchMode="singleTop"` and does NOT contain `android:taskAffinity=""`.
- Run: flutter analyze (must be 0 issues).

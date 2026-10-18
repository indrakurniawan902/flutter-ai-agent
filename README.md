# flutter-ai-agent

Action-oriented mobile AI agent with on-device tool calling, running entirely
on Android and iOS via Flutter.

Built around a clean domain boundary where the LLM is just one driver: the app
exposes device capabilities as structured tools that the model can invoke
during a conversation — camera, calendar, contacts, local files, alarms,
geofences, system settings, and an overlay bubble.

## Architecture

Clean Architecture with strict layer separation:

```
presentation  →  domain (tools, services, entities)  ←  data (remote, local Hive)
```

- **State management:** `flutter_bloc` (Cubit only)
- **Dependency injection:** `get_it` + `injectable`
- **Routing:** `go_router` with shell navigation
- **Local storage:** `hive_ce` (community edition) + `flutter_secure_storage` for credentials
- **Voice & sensory:** `speech_to_text`, `flutter_tts`, `audioplayers`

## Native device tools

Every tool lives under `lib/domain/tools/chat/` behind an interface, callable by
the model runtime:

- **Sensory & vision:** `camera_vision_service`, `voice_input_service`, `voice_output_service`
- **Device context:** `device_context_service`, `battery_optimization_service`, `location_service`
- **System integration:** `intent_launcher_service`, `calendar_service`, `contact_launcher_tools`, `exact_alarm_service`
- **Workspace & memory:** `file_workspace_service`, `local_memory_service`, `notification_triage_service`
- **UI chrome:** `overlay_bubble_service` (system alert window), `geofence_management_screen`

## Requirements

- Flutter SDK `^3.10.0`
- Android SDK 34+ (for fine-grained alarms, overlay, and background execution)
- iOS 15+

/// Contract for exact-alarm (`SCHEDULE_EXACT_ALARM`) availability so screens
/// can self-diagnose alarm scheduling without touching platform channels.
abstract class ExactAlarmServiceBase {
  Future<bool> canScheduleExactAlarms();
  Future<bool> openExactAlarmSettings();
}

import '../models/member_position.dart';
import 'notification_service.dart';

/// Locally watches crew positions and fires an alert the first time a member
/// crosses the silence threshold. (Without push, detection is per-device: each
/// phone notices when a peer it can see goes quiet.)
class DeadManMonitor {
  DeadManMonitor(this._notifications);

  final NotificationService _notifications;
  final Set<String> _alerted = {};

  void evaluate(
    List<MemberPosition> members, {
    required bool enabled,
    required int thresholdMinutes,
  }) {
    if (!enabled) {
      _alerted.clear();
      return;
    }
    final threshold = Duration(minutes: thresholdMinutes);
    for (final m in members) {
      if (m.isSelf) continue;
      if (m.age > threshold) {
        if (_alerted.add(m.userId)) {
          _notifications.show(
            '${m.callsign} went quiet',
            'No ping from ${m.callsign} in $thresholdMinutes+ min.',
          );
        }
      } else {
        _alerted.remove(m.userId); // back online → re-arm
      }
    }
  }
}

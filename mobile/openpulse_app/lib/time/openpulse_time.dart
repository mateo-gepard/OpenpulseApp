import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class OpenPulseTime {
  static const timeZoneName = 'Europe/Berlin';
  static bool _initialized = false;
  static late final timezone.Location _berlin;

  static timezone.Location get berlin {
    _ensureInitialized();
    return _berlin;
  }

  static DateTime now() => timezone.TZDateTime.now(berlin);

  static DateTime dayStart(DateTime instant) {
    final berlinTime = timezone.TZDateTime.from(instant, berlin);
    return timezone.TZDateTime(
      berlin,
      berlinTime.year,
      berlinTime.month,
      berlinTime.day,
    );
  }

  static DateTime nextDayStart(DateTime day) {
    final berlinTime = timezone.TZDateTime.from(day, berlin);
    return timezone.TZDateTime(
      berlin,
      berlinTime.year,
      berlinTime.month,
      berlinTime.day + 1,
    );
  }

  static DateTime previousDayStart(DateTime day) {
    final berlinTime = timezone.TZDateTime.from(day, berlin);
    return timezone.TZDateTime(
      berlin,
      berlinTime.year,
      berlinTime.month,
      berlinTime.day - 1,
    );
  }

  static bool isAfterToday(DateTime day) {
    return dayStart(day).isAfter(dayStart(now()));
  }

  static String clock(DateTime instant) {
    final berlinTime = timezone.TZDateTime.from(instant, berlin);
    final hour = berlinTime.hour.toString().padLeft(2, '0');
    final minute = berlinTime.minute.toString().padLeft(2, '0');
    final second = berlinTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String dayLabel(DateTime day) {
    final berlinDay = dayStart(day);
    final today = dayStart(now());
    if (berlinDay.millisecondsSinceEpoch == today.millisecondsSinceEpoch) {
      return 'TODAY';
    }
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${berlinDay.day} ${months[berlinDay.month - 1]}';
  }

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    timezone_data.initializeTimeZones();
    _berlin = timezone.getLocation(timeZoneName);
    _initialized = true;
  }
}

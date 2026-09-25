import '../features/attendance/attendance_model.dart';
import '../features/subject/subject_model.dart';

class AttendanceMath {
  /// Calculates how many consecutive upcoming classes can be bunked while keeping
  /// attendance at or above [targetPercentage].
  ///
  /// Formula: k = floor((attended - targetRatio * marked) / targetRatio)
  /// Returns 0 if already below target or if no classes can be bunked.
  static int calculateBunkableClasses({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0 || targetPercentage <= 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;
    if (currentRatio < targetRatio) return 0;

    int bunkable = ((attended - targetRatio * marked) / targetRatio + 1e-9).floor();
    if (bunkable < 0) bunkable = 0;
    while (bunkable > 0 && (attended / (marked + bunkable)) < targetRatio) {
      bunkable--;
    }
    while ((attended / (marked + bunkable + 1)) >= targetRatio) {
      bunkable++;
    }
    return bunkable;
  }

  /// Calculates how many consecutive upcoming classes must be attended to reach
  /// [targetPercentage].
  ///
  /// Formula: x = ceil((targetRatio * marked - attended) / (1 - targetRatio))
  /// Returns 0 if already at or above target.
  /// Returns -1 if target >= 100% and attendance < 100% (unreachable).
  static int calculateClassesNeededToReachTarget({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;
    if (currentRatio >= targetRatio) return 0;
    if (targetRatio >= 1.0) {
      // Cannot reach 100% if already missed classes
      return -1;
    }

    int needed = ((targetRatio * marked - attended) / (1.0 - targetRatio) - 1e-9).ceil();
    if (needed < 1) needed = 1;
    while ((attended + needed) / (marked + needed) < targetRatio) {
      needed++;
    }
    while (needed > 1 && (attended + needed - 1) / (marked + needed - 1) >= targetRatio) {
      needed--;
    }
    return needed;
  }

  /// Calculates the signed bunkable metric:
  /// - Positive (+k): number of classes you can safely bunk and remain >= target.
  /// - 0: attendance is exactly at target or no marked classes.
  /// - Negative (-x): number of consecutive classes you must attend to get back to target.
  static int calculateBunkableDeficitOrSurplus({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;

    if (currentRatio > targetRatio) {
      return calculateBunkableClasses(
        attended: attended,
        marked: marked,
        targetPercentage: targetPercentage,
      );
    } else if (currentRatio < targetRatio) {
      final needed = calculateClassesNeededToReachTarget(
        attended: attended,
        marked: marked,
        targetPercentage: targetPercentage,
      );
      if (needed == -1) {
        // Target is 100% and unattainable; deficit is at least marked - attended
        return -(marked - attended);
      }
      return -needed;
    } else {
      return 0;
    }
  }

  /// Calculates the custom attendance percentage based on the percentage-point adjustment model:
  /// Starting/Baseline percentage + sum of configured adjustments for each applicable attendance record
  /// that occurs ON or AFTER [config.effectiveFrom].
  static double calculateCustomAttendancePercentage({
    required CustomAttendanceConfig config,
    required Iterable<Attendance> records,
  }) {
    if (!config.isEnabled) {
      return 100.0;
    }

    final normalizedEffectiveFrom =
        normalizeDate(config.effectiveFrom) ?? config.effectiveFrom;
    double current = config.baselinePercentage;

    for (final record in records) {
      final slotKey = record.slotKey ?? '';
      // Exclude internal manual override marker slots if any
      if (slotKey.startsWith('__manual_override_v1__')) {
        continue;
      }

      final recordDate = normalizeDate(record.date) ?? record.date;
      if (recordDate.isBefore(normalizedEffectiveFrom)) {
        continue;
      }

      switch (record.status) {
        case AttendanceStatus.attended:
          current += config.presentAdjustment;
          break;
        case AttendanceStatus.absent:
          current += config.absentAdjustment;
          break;
        case AttendanceStatus.cancelled:
          current += config.cancelledAdjustment;
          break;
        case AttendanceStatus.plannedAbsent:
          current += config.plannedAbsentAdjustment;
          break;
      }
    }

    if (current.isNaN || current.isInfinite) {
      return config.baselinePercentage.clamp(0.0, 100.0);
    }

    // Eliminate IEEE 754 floating point precision errors (e.g. 69.79999999999998 -> 69.8)
    final rounded = (current * 10000).round() / 10000;
    return rounded.clamp(0.0, 100.0);
  }

  /// Calculates how many upcoming classes can be bunked (each deducting [absentAdjustment])
  /// while keeping attendance at or above [targetPercentage].
  static int calculateCustomBunkableClasses({
    required double currentPercentage,
    required double absentAdjustment,
    required double targetPercentage,
  }) {
    if (currentPercentage < targetPercentage) return 0;
    if (absentAdjustment >= 0) return 0;

    final lossPerBunk = -absentAdjustment;
    int bunkable = ((currentPercentage - targetPercentage) / lossPerBunk + 1e-9).floor();
    if (bunkable < 0) bunkable = 0;

    while (bunkable > 0 &&
        (((currentPercentage - (bunkable * lossPerBunk)) * 10000).round() / 10000) < targetPercentage) {
      bunkable--;
    }
    while ((((currentPercentage - ((bunkable + 1) * lossPerBunk)) * 10000).round() / 10000) >=
        targetPercentage) {
      bunkable++;
    }
    return bunkable;
  }

  /// Calculates how many upcoming classes must be attended (each adding [presentAdjustment])
  /// to reach [targetPercentage].
  /// Returns -1 if presentAdjustment <= 0 (unreachable).
  static int calculateCustomClassesNeededToReachTarget({
    required double currentPercentage,
    required double presentAdjustment,
    required double targetPercentage,
  }) {
    if (currentPercentage >= targetPercentage) return 0;
    if (presentAdjustment <= 0) return -1;

    int needed =
        ((targetPercentage - currentPercentage) / presentAdjustment - 1e-9).ceil();
    if (needed < 1) needed = 1;

    while ((((currentPercentage + (needed * presentAdjustment)) * 10000).round() / 10000) <
        targetPercentage) {
      needed++;
    }
    while (needed > 1 &&
        (((currentPercentage + ((needed - 1) * presentAdjustment)) * 10000).round() / 10000) >=
            targetPercentage) {
      needed--;
    }
    return needed;
  }

  /// Calculates the signed bunkable metric in custom percentage-point mode.
  static int calculateCustomBunkableDeficitOrSurplus({
    required double currentPercentage,
    required double presentAdjustment,
    required double absentAdjustment,
    required double targetPercentage,
  }) {
    if (currentPercentage > targetPercentage) {
      return calculateCustomBunkableClasses(
        currentPercentage: currentPercentage,
        absentAdjustment: absentAdjustment,
        targetPercentage: targetPercentage,
      );
    } else if (currentPercentage < targetPercentage) {
      final needed = calculateCustomClassesNeededToReachTarget(
        currentPercentage: currentPercentage,
        presentAdjustment: presentAdjustment,
        targetPercentage: targetPercentage,
      );
      if (needed == -1) {
        return -999;
      }
      return -needed;
    } else {
      return 0;
    }
  }
}


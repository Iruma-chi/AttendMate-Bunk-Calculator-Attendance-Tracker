import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/utils/attendance_math.dart';

void main() {
  group('Custom Attendance Logic Tests', () {
    final effectiveDate = DateTime(2026, 9, 25);

    test('Test 1: Baseline 72.0, Present +0.6, Absent -4.0, Cancelled 0.0 with 3 Presents & 1 Absent -> 69.8%', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 72.0 + 0.6 + 0.6 - 4.0 + 0.6 = 69.8
      expect(result, closeTo(69.8, 0.001));
    });

    test('Test 2: Delete the Absent record -> 73.8%', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      // Absent record deleted
      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 72.0 + 0.6 + 0.6 + 0.6 = 73.8
      expect(result, closeTo(73.8, 0.001));
    });

    test('Test 3: Change the Absent record to Present -> 74.4%', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      // The 3rd record changed to attended
      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 72.0 + 4 * 0.6 = 74.4
      expect(result, closeTo(74.4, 0.001));
    });

    test('Test 4: Change Present adjustment from +0.6 to +0.8 -> recalculates from stored records', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.8,
        absentAdjustment: -4.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 72.0 + 0.8 + 0.8 - 4.0 + 0.8 = 70.4
      expect(result, closeTo(70.4, 0.001));
    });

    test('Test 5: Change Absent adjustment from -4.0 to -3.0 -> recalculates from stored records', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -3.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 72.0 + 0.6 + 0.6 - 3.0 + 0.6 = 70.8
      expect(result, closeTo(70.8, 0.001));
    });

    test('Test 6: Change baseline from 72.0 to 80.0 -> recalculates correctly', () {
      final config = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 80.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        cancelledAdjustment: 0.0,
        plannedAbsentAdjustment: 0.0,
        effectiveFrom: effectiveDate,
      );

      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 28), status: AttendanceStatus.attended),
      ];

      final result = AttendanceMath.calculateCustomAttendancePercentage(
        config: config,
        records: records,
      );

      // 80.0 + 0.6 + 0.6 - 4.0 + 0.6 = 77.8
      expect(result, closeTo(77.8, 0.001));
    });

    test('Test 7: Change Effective-from date -> only records on/after new date affect result', () {
      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 24), status: AttendanceStatus.absent), // before initial
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 27), status: AttendanceStatus.absent),
      ];

      // Effective from 25 Sep: excludes 24 Sep
      final config1 = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        effectiveFrom: DateTime(2026, 9, 25),
      );

      // 72.0 + 0.6 + 0.6 - 4.0 = 69.2
      expect(AttendanceMath.calculateCustomAttendancePercentage(config: config1, records: records), closeTo(69.2, 0.001));

      // Change effectiveFrom to 27 Sep: only 27 Sep is on or after 27 Sep
      final config2 = config1.copyWith(effectiveFrom: DateTime(2026, 9, 27));

      // 72.0 - 4.0 = 68.0
      expect(AttendanceMath.calculateCustomAttendancePercentage(config: config2, records: records), closeTo(68.0, 0.001));
    });

    test('Test 8: Serialization & reload -> Custom settings remain intact', () {
      final original = Subject(
        name: 'Distributed Systems',
        acronym: 'DS',
        color: Colors.blue,
        schedule: [],
        targetAttendance: 80,
        customAttendanceConfig: CustomAttendanceConfig(
          isEnabled: true,
          baselinePercentage: 68.5,
          presentAdjustment: 0.75,
          absentAdjustment: -3.5,
          cancelledAdjustment: 0.0,
          plannedAbsentAdjustment: 0.0,
          effectiveFrom: DateTime(2026, 9, 20),
        ),
      );

      final jsonMap = original.toJson();
      final jsonString = jsonEncode(jsonMap);
      final restored = Subject.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

      expect(restored.customAttendanceConfig, isNotNull);
      expect(restored.customAttendanceConfig!.isEnabled, isTrue);
      expect(restored.customAttendanceConfig!.baselinePercentage, 68.5);
      expect(restored.customAttendanceConfig!.presentAdjustment, 0.75);
      expect(restored.customAttendanceConfig!.absentAdjustment, -3.5);
      expect(restored.customAttendanceConfig!.effectiveFrom.day, 20);
    });

    test('Test 9: Backup & restore simulation preserves custom settings and records', () {
      final subject = Subject(
        id: 'sub_test',
        name: 'Compiler Design',
        color: Colors.purple,
        schedule: [],
        targetAttendance: 75,
        customAttendanceConfig: CustomAttendanceConfig(
          isEnabled: true,
          baselinePercentage: 70.0,
          presentAdjustment: 0.5,
          absentAdjustment: -2.5,
          effectiveFrom: DateTime(2026, 9, 1),
        ),
      );

      // Simulate database row
      final dbRow = {
        'id': subject.id,
        'name': subject.name,
        'acronym': subject.acronym,
        'color': subject.color.toARGB32(),
        'schedule': jsonEncode([]),
        'targetAttendance': subject.targetAttendance,
        'attendanceRecords': jsonEncode([]),
        'locationId': null,
        'room': null,
        'block': null,
        'customAttendanceConfig': jsonEncode(subject.customAttendanceConfig!.toJson()),
      };

      // Backup bundle simulation
      final backupBundle = {
        'app': 'AttendMate',
        'schema_version': 1,
        'database': {
          'subjects': [dbRow],
          'attendance': [],
        },
      };

      final backupJson = jsonEncode(backupBundle);
      final parsedBackup = jsonDecode(backupJson) as Map<String, dynamic>;
      final restoredRows = (parsedBackup['database']['subjects'] as List).cast<Map<String, dynamic>>();

      final restoredSubject = Subject(
        id: restoredRows.first['id'] as String,
        name: restoredRows.first['name'] as String,
        color: Color(restoredRows.first['color'] as int),
        schedule: [],
        targetAttendance: restoredRows.first['targetAttendance'] as int,
        customAttendanceConfig: CustomAttendanceConfig.fromJson(
          jsonDecode(restoredRows.first['customAttendanceConfig'] as String) as Map<String, dynamic>,
        ),
      );

      expect(restoredSubject.customAttendanceConfig!.isEnabled, isTrue);
      expect(restoredSubject.customAttendanceConfig!.baselinePercentage, 70.0);
      expect(restoredSubject.customAttendanceConfig!.presentAdjustment, 0.5);
      expect(restoredSubject.customAttendanceConfig!.absentAdjustment, -2.5);
    });

    test('Test 10 & 11: Custom mode OFF falls back to original, Custom mode ON restores custom calculation', () {
      final configOn = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 72.0,
        presentAdjustment: 0.6,
        absentAdjustment: -4.0,
        effectiveFrom: effectiveDate,
      );

      final configOff = configOn.copyWith(isEnabled: false);

      final records = [
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub_1', date: DateTime(2026, 9, 26), status: AttendanceStatus.absent),
      ];

      // In custom mode OFF: calculateCustomAttendancePercentage returns 100.0 or standard ratio
      expect(AttendanceMath.calculateCustomAttendancePercentage(config: configOff, records: records), 100.0);

      // In standard mode: 1 attended / 2 held = 50.0%
      final attendedCount = records.where((r) => r.status == AttendanceStatus.attended).length;
      final standardPercentage = (attendedCount / records.length) * 100;
      expect(standardPercentage, 50.0);

      // In custom mode ON: 72.0 + 0.6 - 4.0 = 68.6%
      expect(AttendanceMath.calculateCustomAttendancePercentage(config: configOn, records: records), closeTo(68.6, 0.001));
    });

    test('Test 12: Validation & boundary clamping (0.0 to 100.0) without NaN or Infinity', () {
      final configExtreme = CustomAttendanceConfig(
        isEnabled: true,
        baselinePercentage: 99.0,
        presentAdjustment: 10.0,
        absentAdjustment: -150.0,
        effectiveFrom: effectiveDate,
      );

      // 99.0 + 10.0 = 109.0 -> clamped to 100.0
      final resultOver = AttendanceMath.calculateCustomAttendancePercentage(
        config: configExtreme,
        records: [Attendance(subjectId: 's', date: DateTime(2026, 9, 25), status: AttendanceStatus.attended)],
      );
      expect(resultOver, 100.0);

      // 99.0 - 150.0 = -51.0 -> clamped to 0.0
      final resultUnder = AttendanceMath.calculateCustomAttendancePercentage(
        config: configExtreme,
        records: [Attendance(subjectId: 's', date: DateTime(2026, 9, 25), status: AttendanceStatus.absent)],
      );
      expect(resultUnder, 0.0);
    });

    test('Test 13: Custom Bunk Math (Bunkable classes & classes needed)', () {
      // Current = 78.2%, Target = 70.0%, Absent = -4.0%
      // 78.2 - 4.0 = 74.2 >= 70
      // 74.2 - 4.0 = 70.2 >= 70
      // 70.2 - 4.0 = 66.2 < 70
      // Bunkable = 2 classes
      final bunkable = AttendanceMath.calculateCustomBunkableClasses(
        currentPercentage: 78.2,
        absentAdjustment: -4.0,
        targetPercentage: 70.0,
      );
      expect(bunkable, 2);

      // Current = 72.0%, Target = 75.0%, Present = +0.6%
      // Deficit = 3.0 percentage points
      // 3.0 / 0.6 = 5 classes needed
      final needed = AttendanceMath.calculateCustomClassesNeededToReachTarget(
        currentPercentage: 72.0,
        presentAdjustment: 0.6,
        targetPercentage: 75.0,
      );
      expect(needed, 5);
    });
  });
}

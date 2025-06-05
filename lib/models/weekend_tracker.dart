import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class WeekendTracker {
  static const String lastBigWeekendKey = 'lastBigWeekend';
  static const String manualOverrideKey = 'manualWeekendOverride';
  static const String manualOverrideValueKey = 'manualWeekendOverrideValue';
  
  // Check if today is a workday
  static Future<bool> isWorkday() async {
    final now = DateTime.now();
    final currentWeekday = now.weekday; // Monday is 1, Sunday is 7
    
    // Monday is always a day off
    if (currentWeekday == DateTime.monday) {
      return false;
    }
    
    // If it's Tuesday, check if it's a big weekend week
    if (currentWeekday == DateTime.tuesday) {
      final isBigWeekend = await isBigWeekendWeek();
      return !isBigWeekend; // If big weekend, Tuesday is off
    }
    
    // All other days are workdays
    return true;
  }
  
  // Check if this is currently a big weekend week
  static Future<bool> isBigWeekendWeek() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if there's a manual override
    final hasOverride = prefs.getBool(manualOverrideKey) ?? false;
    if (hasOverride) {
      return prefs.getBool(manualOverrideValueKey) ?? false;
    }
    
    final now = DateTime.now();
    
    // Get the timestamp of the last big weekend (where both Mon+Tue were off)
    final lastBigWeekendTimestamp = prefs.getInt(lastBigWeekendKey) ?? 0;
    
    if (lastBigWeekendTimestamp == 0) {
      // If no record exists, assume it's a big weekend week (first time setup)
      return true;
    }
    
    final lastBigWeekend = DateTime.fromMillisecondsSinceEpoch(lastBigWeekendTimestamp);
    
    // Calculate the number of weeks since the last big weekend
    final daysSinceLastBigWeekend = now.difference(lastBigWeekend).inDays;
    final weeksSinceLastBigWeekend = (daysSinceLastBigWeekend / 7).floor();
    
    // If odd number of weeks, it's a small weekend; if even, it's a big weekend
    final isBigWeekend = weeksSinceLastBigWeekend % 2 == 0;
    
    return isBigWeekend;
  }
  
  // Mark today as a big weekend (for keeping track of the cycle)
  static Future<void> markBigWeekend() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt(lastBigWeekendKey, now.millisecondsSinceEpoch);
    // Clear any manual override
    await prefs.setBool(manualOverrideKey, false);
    debugPrint('Marked today (${now.toIso8601String()}) as the latest big weekend');
  }
  
  // Reset the big weekend tracking (for testing or manual adjustments)
  static Future<void> resetWeekendTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(lastBigWeekendKey);
    // Clear any manual override
    await prefs.setBool(manualOverrideKey, false);
    debugPrint('Reset weekend tracking');
  }
  
  // Manually set whether this is a big weekend week or not
  static Future<void> setManualWeekendMode(bool isBigWeekend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(manualOverrideKey, true);
    await prefs.setBool(manualOverrideValueKey, isBigWeekend);
    debugPrint('Manually set weekend mode to: ${isBigWeekend ? "Big Weekend" : "Small Weekend"}');
  }
} 
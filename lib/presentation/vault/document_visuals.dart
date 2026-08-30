import 'package:flutter/material.dart';
import 'package:safekeep/domain/models/document_category.dart';

/// Presentation details for each category: a label and an icon.
///
/// Kept out of [DocumentCategory] itself so the domain layer stays free
/// of Flutter — a domain enum that imports `material.dart` cannot be
/// used from a pure Dart test or a background isolate.
///
/// Categories are distinguished by icon and label, never by colour
/// alone: colour-only encoding is invisible to a significant share of
/// users, and this palette deliberately has one accent anyway.
extension DocumentCategoryVisuals on DocumentCategory {
  String get label => switch (this) {
    DocumentCategory.identity => 'Identity',
    DocumentCategory.license => 'Licences',
    DocumentCategory.contract => 'Contracts',
    DocumentCategory.insurance => 'Insurance',
    DocumentCategory.medical => 'Medical',
    DocumentCategory.tax => 'Tax',
    DocumentCategory.other => 'Other',
  };

  IconData get icon => switch (this) {
    DocumentCategory.identity => Icons.badge_outlined,
    DocumentCategory.license => Icons.directions_car_outlined,
    DocumentCategory.contract => Icons.handshake_outlined,
    DocumentCategory.insurance => Icons.umbrella_outlined,
    DocumentCategory.medical => Icons.medical_services_outlined,
    DocumentCategory.tax => Icons.receipt_long_outlined,
    DocumentCategory.other => Icons.folder_outlined,
  };
}

/// Formats a byte count for display.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Formats a date as `12 Mar 2027`.
///
/// Deliberately not numeric: `03/12/2027` is March in one country and
/// December in another, and expiry dates are exactly where that
/// ambiguity would matter.
String formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

import 'package:flutter/foundation.dart';

/// One emergency contact. Holds exactly the columns the real
/// `emergency_contacts` table defines (`database/schema.sql`) —
/// `contact_name` / `contact_phone` (both required), `relationship`
/// (optional), `priority_order` (integer) — so this maps straight onto
/// the backend once that endpoint exists, with no field rework.
@immutable
class EmergencyContact {
  final String contactName;
  final String contactPhone;
  final String? relationship;
  final int priorityOrder;

  const EmergencyContact({
    required this.contactName,
    required this.contactPhone,
    required this.priorityOrder,
    this.relationship,
  });

  EmergencyContact copyWith({int? priorityOrder}) => EmergencyContact(
    contactName: contactName,
    contactPhone: contactPhone,
    relationship: relationship,
    priorityOrder: priorityOrder ?? this.priorityOrder,
  );
}

/// Session-only, in-memory list of the civilian's emergency contacts.
///
/// Deliberately **not** persisted (no `shared_preferences`, no local DB)
/// and **not** sent to any endpoint — no emergency-contacts API exists
/// yet. This is a working preview of the feature that resets on every app
/// restart, on purpose. When the real create/list/delete endpoints land,
/// only these method bodies gain a network call; the surface
/// ([contacts], [add], [removeAt]) and [EmergencyContact]'s fields stay
/// as they are.
class EmergencyContactsStore extends ChangeNotifier {
  final List<EmergencyContact> _contacts = [];

  /// Read-only view — callers mutate through [add] / [removeAt] so
  /// [priorityOrder] stays in sync with list position.
  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);

  /// Appends a contact. [EmergencyContact.priorityOrder] is assigned from
  /// the new list position (1-based); there is no manual reorder UI in
  /// this pass. A blank or whitespace-only [relationship] is stored as
  /// `null`, matching the column being nullable.
  void add({
    required String contactName,
    required String contactPhone,
    String? relationship,
  }) {
    final trimmedRelationship = relationship?.trim();
    _contacts.add(
      EmergencyContact(
        contactName: contactName.trim(),
        contactPhone: contactPhone.trim(),
        relationship: (trimmedRelationship == null || trimmedRelationship.isEmpty)
            ? null
            : trimmedRelationship,
        priorityOrder: _contacts.length + 1,
      ),
    );
    notifyListeners();
  }

  /// Removes the contact at [index] and renumbers the rest so
  /// [EmergencyContact.priorityOrder] stays contiguous (1..n).
  void removeAt(int index) {
    if (index < 0 || index >= _contacts.length) {
      return;
    }
    _contacts.removeAt(index);
    for (var i = 0; i < _contacts.length; i++) {
      if (_contacts[i].priorityOrder != i + 1) {
        _contacts[i] = _contacts[i].copyWith(priorityOrder: i + 1);
      }
    }
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/emergency_contacts_store.dart';
import '../theme/sentri_colors.dart';

/// In-memory Emergency Contacts preview, reached from the Profile tab.
/// Pushed on top of the app shell, so the floating nav bar is
/// intentionally not shown here (same as `SosScreen`).
///
/// Nothing on this screen is persisted or sent anywhere — see
/// [EmergencyContactsStore]. It is a real, working UI previewing a
/// feature whose backend endpoint does not exist yet, not a "coming
/// soon" placeholder.
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<EmergencyContactsStore>().contacts;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: contacts.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: contacts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) => _ContactCard(
                        contact: contacts[index],
                        onRemove: () => context
                            .read<EmergencyContactsStore>()
                            .removeAt(index),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AddEmergencyContactScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add contact'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 40,
              color: SentriColors.textMuted,
            ),
            SizedBox(height: 12),
            Text(
              'No emergency contacts added yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: SentriColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onRemove;

  const _ContactCard({required this.contact, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final relationship = contact.relationship;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: SentriColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.contactName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SentriColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contact.contactPhone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SentriColors.textPrimary,
                  ),
                ),
                if (relationship != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    relationship,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SentriColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            color: SentriColors.textMuted,
            tooltip: 'Remove ${contact.contactName}',
          ),
        ],
      ),
    );
  }
}

/// Full-page add form, mirroring `register_screen.dart`'s
/// `Form` + `TextFormField` + `FilledButton` pattern. Submit is disabled
/// until name and phone both have a value; validators are the backstop.
/// On submit it writes straight to [EmergencyContactsStore] and pops —
/// the same "call the store, then navigate" shape `RegisterScreen` uses.
class AddEmergencyContactScreen extends StatefulWidget {
  const AddEmergencyContactScreen({super.key});

  @override
  State<AddEmergencyContactScreen> createState() =>
      _AddEmergencyContactScreenState();
}

class _AddEmergencyContactScreenState extends State<AddEmergencyContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _relationshipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty;

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    context.read<EmergencyContactsStore>().add(
      contactName: _nameController.text,
      contactPhone: _phoneController.text,
      relationship: _relationshipController.text,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add contact')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Name is required.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Phone number is required.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship (optional)',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: const Text('Add contact'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

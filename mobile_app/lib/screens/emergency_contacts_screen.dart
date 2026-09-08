import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../services/emergency_contacts_store.dart';
import '../theme/sentri_colors.dart';
import '../theme/sentri_text.dart';
import '../theme/sentri_tokens.dart';
import '../widgets/sentri_card.dart';

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
                      padding: const EdgeInsets.all(SentriSpacing.xl),
                      itemCount: contacts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: SentriSpacing.md),
                      itemBuilder: (context, index) => _ContactCard(
                        contact: contacts[index],
                        onRemove: () => context
                            .read<EmergencyContactsStore>()
                            .removeAt(index),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SentriSpacing.xl,
                SentriSpacing.sm,
                SentriSpacing.xl,
                SentriSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AddEmergencyContactScreen(),
                    ),
                  ),
                  icon: const Icon(LucideIcons.plus),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SentriSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.contact,
              size: 40,
              color: SentriColors.textMuted,
            ),
            const SizedBox(height: SentriSpacing.md),
            Text(
              'No emergency contacts added yet',
              textAlign: TextAlign.center,
              style: SentriText.bodySmall.copyWith(color: SentriColors.textMuted),
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
    return SentriCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.contactName,
                  style: SentriText.bodySmall.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(contact.contactPhone, style: SentriText.bodySmall),
                if (relationship != null) ...[
                  const SizedBox(height: 2),
                  Text(relationship, style: SentriText.caption),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(LucideIcons.trash2),
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
          padding: const EdgeInsets.all(SentriSpacing.xl),
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
                const SizedBox(height: SentriSpacing.lg),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Phone number is required.'
                      : null,
                ),
                const SizedBox(height: SentriSpacing.lg),
                TextFormField(
                  controller: _relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship (optional)',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: SentriSpacing.xl),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/brand_guidelines_form.dart';

class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _orgNameController = TextEditingController();
  final _formKey = GlobalKey<BrandGuidelinesFormState>();
  final _inviteEmailController = TextEditingController();
  String _inviteRole = 'member';
  bool _savingBrand = false;
  bool _inviting = false;

  @override
  void initState() {
    super.initState();
    final org = ref.read(authControllerProvider).org;
    _orgNameController.text = org?.name ?? '';
  }

  @override
  void dispose() {
    _orgNameController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _saveBranding() async {
    setState(() => _savingBrand = true);
    try {
      final org = await ref.read(repositoryProvider).updateOrg(
            name: _orgNameController.text.trim(),
            brandGuidelines: _formKey.currentState?.value,
          );
      ref.read(authControllerProvider.notifier).setOrg(org);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Branding saved')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingBrand = false);
      }
    }
  }

  Future<void> _invite() async {
    final email = _inviteEmailController.text.trim();
    if (email.isEmpty) {
      return;
    }
    setState(() => _inviting = true);
    try {
      await ref.read(repositoryProvider).inviteMember(email: email, role: _inviteRole);
      _inviteEmailController.clear();
      await ref.read(authControllerProvider.notifier).refreshOrg();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member invited')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invite failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  Future<void> _changeRole(OrgMember member, String role) async {
    try {
      await ref.read(repositoryProvider).updateMemberRole(member.id, role);
      await ref.read(authControllerProvider.notifier).refreshOrg();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role change failed: $error')),
        );
      }
    }
  }

  Future<void> _removeMember(OrgMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove ${member.name.isEmpty ? member.email : member.name} from the organization?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(repositoryProvider).removeMember(member.id);
      await ref.read(authControllerProvider.notifier).refreshOrg();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(authControllerProvider).org;
    if (org == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final canManage = org.canManage;
    return Scaffold(
      appBar: AppBar(title: const Text('Organization settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Branding', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _orgNameController,
            enabled: canManage && !_savingBrand,
            decoration: const InputDecoration(
              labelText: 'Organization name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          BrandGuidelinesForm(
            key: _formKey,
            enabled: canManage && !_savingBrand,
            initial: org.brandGuidelines,
            title: 'Brand guidelines',
            subtitle: 'Pre-filled on the create page for every new ad',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: (canManage && !_savingBrand) ? _saveBranding : null,
              icon: _savingBrand
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save branding'),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Members', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '${org.members.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...org.members.map((member) => _MemberTile(
                member: member,
                canManage: canManage,
                onChangeRole: (role) => _changeRole(member, role),
                onRemove: () => _removeMember(member),
              )),
          if (canManage) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Invite a teammate',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inviteEmailController,
                      enabled: !_inviting,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'teammate@company.com',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _inviteRole,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'member', child: Text('Member')),
                              DropdownMenuItem(value: 'admin', child: Text('Admin')),
                            ],
                            onChanged: _inviting
                                ? null
                                : (value) => setState(() => _inviteRole = value ?? 'member'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _inviting ? null : _invite,
                          icon: _inviting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add),
                          label: const Text('Invite'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canManage,
    required this.onChangeRole,
    required this.onRemove,
  });

  final OrgMember member;
  final bool canManage;
  final ValueChanged<String> onChangeRole;
  final VoidCallback onRemove;

  static const _roleLabels = {
    'owner': 'Owner',
    'admin': 'Admin',
    'member': 'Member',
  };

  @override
  Widget build(BuildContext context) {
    final isSelfOwner = member.isOwner;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          (member.name.isNotEmpty ? member.name : member.email)
              .substring(0, 1)
              .toUpperCase(),
        ),
      ),
      title: Text(member.name.isEmpty ? member.email : member.name),
      subtitle: Text(member.email),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canManage && !isSelfOwner)
            DropdownButton<String>(
              value: member.role,
              underline: const SizedBox.shrink(),
              items: _roleLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (role) {
                if (role != null) {
                  onChangeRole(role);
                }
              },
            )
          else
            Text(
              _roleLabels[member.role] ?? member.role,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (canManage && !isSelfOwner) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove member',
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}
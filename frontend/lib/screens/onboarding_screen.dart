import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/brand_guidelines_form.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _orgNameController = TextEditingController();
  final _formKey = GlobalKey<BrandGuidelinesFormState>();
  bool _busy = false;

  @override
  void dispose() {
    _orgNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final orgName = _orgNameController.text.trim();
    if (orgName.isEmpty) {
      _showError('Enter your organization name');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding(
            orgName: orgName,
            brandGuidelines: _formKey.currentState?.value,
          );
    } catch (error) {
      if (mounted) {
        _showError('Onboarding failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboard your organization')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set up your workspace',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Organizations, not users, hold the brand preferences. '
                  'They are saved here and pre-filled on every ad you create.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _orgNameController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Organization name',
                    hintText: 'e.g. Mango Maja Farms',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                BrandGuidelinesForm(
                  key: _formKey,
                  enabled: !_busy,
                  title: 'Brand guidelines',
                  subtitle: 'Saved for your organization - you can change these later',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Start creating ads'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
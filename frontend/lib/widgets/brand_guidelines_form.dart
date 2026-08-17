import 'package:flutter/material.dart';

import '../models/models.dart';

class BrandGuidelinesForm extends StatefulWidget {
  const BrandGuidelinesForm({super.key, this.enabled = true});

  final bool enabled;

  @override
  BrandGuidelinesFormState createState() => BrandGuidelinesFormState();
}

class BrandGuidelinesFormState extends State<BrandGuidelinesForm> {
  final _brandName = TextEditingController();
  final _tagline = TextEditingController();
  final _tone = TextEditingController();
  final _colors = TextEditingController();
  final _typography = TextEditingController();
  final _visualStyle = TextEditingController();
  final _doList = TextEditingController();
  final _dontList = TextEditingController();
  final _audience = TextEditingController();

  @override
  void dispose() {
    _brandName.dispose();
    _tagline.dispose();
    _tone.dispose();
    _colors.dispose();
    _typography.dispose();
    _visualStyle.dispose();
    _doList.dispose();
    _dontList.dispose();
    _audience.dispose();
    super.dispose();
  }

  List<String>? _split(String value) {
    final parts = value
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts;
  }

  String? _trim(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  BrandGuidelines? get value {
    final guidelines = BrandGuidelines(
      brandName: _trim(_brandName),
      tagline: _trim(_tagline),
      toneOfVoice: _trim(_tone),
      colors: _split(_colors.text),
      typography: _trim(_typography),
      visualStyle: _trim(_visualStyle),
      doList: _split(_doList.text),
      dontList: _split(_dontList.text),
      targetAudience: _trim(_audience),
    );
    return guidelines.isEmpty ? null : guidelines;
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: widget.enabled,
        minLines: maxLines > 1 ? 1 : null,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text('Brand guidelines (optional)'),
        subtitle: const Text(
          'Tone, colors, typography, do\'s and don\'ts',
          style: TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_brandName, 'Brand name'),
          _field(_tagline, 'Tagline / positioning'),
          _field(_tone, 'Tone of voice',
              hint: 'e.g. warm, confident, playful', maxLines: 2),
          _field(_colors, 'Color palette',
              hint: 'e.g. #E8B4B8, #4A2C2A, cream', maxLines: 2),
          _field(_typography, 'Typography',
              hint: 'e.g. bold geometric sans-serif'),
          _field(_visualStyle, 'Visual style',
              hint: 'e.g. moody product photography, golden hour', maxLines: 2),
          _field(_doList, 'Always do', hint: 'e.g. hero the product, show hands', maxLines: 2),
          _field(_dontList, 'Never do',
              hint: 'e.g. no cliches, no stock-looking models', maxLines: 2),
          _field(_audience, 'Target audience', maxLines: 2),
        ],
      ),
    );
  }
}
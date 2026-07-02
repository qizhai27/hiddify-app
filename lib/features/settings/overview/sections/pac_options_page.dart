import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PacOptionsPage extends HookConsumerWidget {
  const PacOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final pacUrl = ref.watch(Preferences.pacUrl);
    final pacEnabled = ref.watch(Preferences.pacEnabled);
    final customRules = ref.watch(Preferences.pacCustomRules);

    final urlController = useTextEditingController(text: pacUrl);
    final rulesController = useTextEditingController(text: customRules.join('\n'));

    useEffect(() {
      urlController.text = pacUrl;
      return null;
    }, [pacUrl]);

    useEffect(() {
      rulesController.text = customRules.join('\n');
      return null;
    }, [customRules]);

    final validationResults = useState<_ValidationResult>(const _ValidationResult(valid: [], invalid: []));

    useEffect(() {
      void validate() {
        final lines = rulesController.text.split('\n');
        final valid = <String>[];
        final invalid = <_InvalidLine>[];

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || line.startsWith('!') || line.startsWith('#')) {
            continue;
          }
          if (_isValidRule(line)) {
            valid.add(line);
          } else {
            invalid.add(_InvalidLine(lineNumber: i + 1, content: lines[i]));
          }
        }

        validationResults.value = _ValidationResult(valid: valid, invalid: invalid);
      }

      validate();
      rulesController.addListener(validate);
      return () => rulesController.removeListener(validate);
    }, [rulesController]);

    final hasInvalidLines = validationResults.value.invalid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.pac.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: t.pages.settings.pac.rulesHelp,
            onPressed: () => _showRulesHelp(context, t),
          ),
          Switch.adaptive(
            value: pacEnabled,
            onChanged: (value) async {
              await ref.read(Preferences.pacEnabled.notifier).update(value);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: t.pages.settings.pac.pacUrl,
                border: const OutlineInputBorder(),
              ),
              maxLines: null,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: rulesController,
                decoration: InputDecoration(
                  labelText: t.pages.settings.pac.customRules,
                  hintText: t.pages.settings.pac.customRulesHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            if (hasInvalidLines) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.pages.settings.pac.invalidRules,
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...validationResults.value.invalid.map(
                      (e) => Text(
                        "${t.pages.settings.pac.line} ${e.lineNumber}: ${e.content}",
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: hasInvalidLines
                  ? null
                  : () async {
                      await ref.read(Preferences.pacUrl.notifier).update(urlController.text);
                      await ref.read(Preferences.pacCustomRules.notifier).update(validationResults.value.valid);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t.pages.settings.pac.saveSuccess)),
                        );
                      }
                    },
              child: Text(t.pages.settings.pac.save),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isValidRule(String line) {
    if (line.startsWith('@@')) {
      return _isValidRule(line.substring(2));
    }

    if (line.startsWith('||')) {
      final domain = line.substring(2).split('/').first.split(':').first;
      return _isValidDomain(domain);
    }

    if (line.startsWith('|http://') || line.startsWith('|https://')) {
      final url = line.substring(1);
      final uri = Uri.tryParse(url);
      return uri != null && uri.host.isNotEmpty;
    }

    if (line.startsWith('/')) {
      return line.endsWith('/') && line.length > 2;
    }

    if (line.startsWith('.')) {
      return _isValidDomain(line.substring(1));
    }

    if (line.contains('.')) {
      return _isValidDomain(line);
    }

    return false;
  }

  static bool _isValidDomain(String domain) {
    if (domain.isEmpty) return false;
    if (domain.contains(' ')) return false;

    final domainPattern = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$',
    );

    if (domain.contains('*')) {
      final parts = domain.split('.');
      for (final part in parts) {
        if (part == '*') continue;
        if (!RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$').hasMatch(part)) return false;
      }
      return true;
    }

    return domainPattern.hasMatch(domain);
  }

  static void _showRulesHelp(BuildContext context, dynamic t) {
    final pac = t.pages.settings.pac;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pac.rulesHelp),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pac.rulesHelpDesc, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              Text(pac.rulesHelpRules.domainMatch, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text(pac.rulesHelpRules.exactMatch, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text(pac.rulesHelpRules.subdomainMatch, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text(pac.rulesHelpRules.whitelist, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Text(pac.rulesHelpRules.comment, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              const Divider(height: 24),
              Text(pac.rulesHelpExamples, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '||google.com\n'
                  '@@||baidu.com\n'
                  '.github.com\n'
                  '! this is a comment',
                  style: TextStyle(fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _ValidationResult {
  final List<String> valid;
  final List<_InvalidLine> invalid;

  const _ValidationResult({required this.valid, required this.invalid});
}

class _InvalidLine {
  final int lineNumber;
  final String content;

  const _InvalidLine({required this.lineNumber, required this.content});
}

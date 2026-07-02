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
    final controller = useTextEditingController(text: pacUrl);

    useEffect(() {
      controller.text = pacUrl;
      return null;
    }, [pacUrl]);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.pac.title),
        actions: [
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
              controller: controller,
              decoration: InputDecoration(
                labelText: t.pages.settings.pac.pacUrl,
                border: const OutlineInputBorder(),
              ),
              maxLines: null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await ref.read(Preferences.pacUrl.notifier).update(controller.text);
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
}

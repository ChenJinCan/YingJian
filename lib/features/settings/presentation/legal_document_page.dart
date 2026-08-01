import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yingjian/l10n/l10n.dart';

enum LegalDocumentType { privacy, terms }

final class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.type, super.key});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode == 'zh'
        ? 'zh'
        : 'en';
    final name = switch (type) {
      LegalDocumentType.privacy => 'privacy',
      LegalDocumentType.terms => 'terms',
    };
    final title = switch (type) {
      LegalDocumentType.privacy => context.l10n.privacyPolicy,
      LegalDocumentType.terms => context.l10n.termsOfUse,
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('assets/legal/${name}_$language.md'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(context.l10n.legalDocumentLoadFailed));
          }
          final document = snapshot.data;
          if (document == null) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
              children: _buildDocument(context, document),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildDocument(BuildContext context, String document) {
    final widgets = <Widget>[];
    for (final rawLine in document.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 12));
      } else if (line.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.substring(2),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              line.substring(3),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      } else {
        widgets.add(
          Text(
            line,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        );
      }
    }
    return widgets;
  }
}

import 'package:flutter/material.dart';

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme.bodyMedium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sansebas Stock - Error'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: textTheme?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.error,
                  ) ??
                  TextStyle(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

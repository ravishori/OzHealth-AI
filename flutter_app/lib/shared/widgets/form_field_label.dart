import 'package:flutter/material.dart';

/// Small all-caps label placed above a form field.
class FormFieldLabel extends StatelessWidget {
  final String text;
  final double bottomPadding;

  const FormFieldLabel(this.text, {super.key, this.bottomPadding = 6});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'admin_look.dart';

/// Shared presentation helpers for the admin form screens. They put the
/// existing raw-map form logic in Plexfin's admin look (AdminLook) without
/// changing how callers read or write their config maps.

Widget adminScreenHeader(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData? icon,
}) {
  // Plex titles its settings pages with plain text; [icon] stays in the
  // signature for the callers, which pass one each.
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.spaceLg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AdminLook.text,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AdminLook.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget adminSectionLabel(BuildContext context, String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      0,
      AppSpacing.spaceXl,
      0,
      AppSpacing.spaceSm,
    ),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AdminLook.muted),
          const SizedBox(width: 6),
        ],
        Text(text.toUpperCase(), style: AdminLook.sectionStyle),
      ],
    ),
  );
}

/// A [adminSectionLabel] followed by [adminGlassGroup] of [children].
Widget adminSection(
  BuildContext context, {
  required String title,
  IconData? icon,
  required List<Widget> children,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      adminSectionLabel(context, title, icon: icon),
      adminGlassGroup(context, children: children),
    ],
  );
}

/// One row of a scrolling list, set off by a thin outline.
Widget adminListCard({required Widget child, EdgeInsetsGeometry? margin}) {
  return Container(
    margin: margin,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: AdminLook.borderRadius,
      border: Border.all(color: AdminLook.line),
    ),
    child: child,
  );
}

/// Groups [children] straight on the page, with thin lines above, between
/// and below them, as Plex lists its settings. (The name is upstream's, from
/// when the group was a glass card.)
Widget adminGlassGroup(BuildContext context, {required List<Widget> children}) {
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) rows.add(_hairline());
    rows.add(children[i]);
  }
  return DecoratedBox(
    decoration: const BoxDecoration(
      border: Border.symmetric(horizontal: BorderSide(color: AdminLook.line)),
    ),
    // Rows paint their hover and press highlight on the nearest Material.
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    ),
  );
}

Widget _hairline() =>
    const Divider(height: 1, thickness: 1, color: AdminLook.line);

InputDecoration adminInputDecoration({
  String? label,
  String? hint,
  String? helper,
  String? suffixText,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: AdminLook.borderRadius,
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    filled: true,
    fillColor: AdminLook.raised,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.spaceLg,
      vertical: 16,
    ),
    floatingLabelStyle: const TextStyle(
      color: AdminLook.gold,
      fontWeight: FontWeight.w600,
    ),
    border: border(AdminLook.line, 1),
    enabledBorder: border(AdminLook.line, 1),
    focusedBorder: border(AdminLook.gold, 1.5),
    suffixText: suffixText,
    suffixIcon: suffixIcon,
  );
}

/// Dropdown of `(code, displayName)` pairs with a leading "default" option.
/// Dedupes by code (the localization lists can repeat codes) and preserves an
/// unknown [current] value so saving never silently drops it. Falls back to a
/// free-text field when [rawItems] is empty (older servers expose no list).
Widget adminCodeDropdown({
  required String label,
  required String defaultLabel,
  required String current,
  required Iterable<(String?, String?)> rawItems,
  required ValueChanged<String?> onChanged,
}) {
  final seen = <String>{};
  final items = <(String, String)>[];
  for (final e in rawItems) {
    final code = e.$1;
    final name = e.$2;
    if (code == null || name == null) continue;
    if (!seen.add(code)) continue;
    items.add((code, name));
  }
  if (items.isEmpty) {
    return TextFormField(
      initialValue: current,
      decoration: adminInputDecoration(label: label),
      onChanged: onChanged,
    );
  }
  final hasCurrent = current.isEmpty || items.any((e) => e.$1 == current);
  return DropdownButtonFormField<String>(
    initialValue: current,
    isExpanded: true,
    decoration: adminInputDecoration(label: label),
    items: [
      DropdownMenuItem(value: '', child: Text(defaultLabel)),
      ...items.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))),
      if (!hasCurrent) DropdownMenuItem(value: current, child: Text(current)),
    ],
    onChanged: onChanged,
  );
}

Widget adminSwitchRow({
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return SwitchListTile.adaptive(
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: AdminLook.muted),
          ),
    value: value,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.spaceLg,
      vertical: 2,
    ),
    onChanged: onChanged,
  );
}

/// Plex's gold Save button, at the start of the row, with a spinner while
/// [saving].
Widget adminSaveButton({
  required String label,
  required bool saving,
  required VoidCallback onPressed,
}) {
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: FilledButton(
      onPressed: saving ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AdminLook.gold,
        foregroundColor: AdminLook.onGold,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: AdminLook.borderRadius),
      ),
      child: saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdminLook.onGold,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
    ),
  );
}

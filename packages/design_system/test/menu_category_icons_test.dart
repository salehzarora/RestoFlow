import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// MENU-CATEGORY-ICON-PICKER-OPS-044 Phase 1 — the registry contract.
///
/// Two of these tests exist because the failure they guard is INVISIBLE here:
/// icon tree-shaking only runs in a RELEASE build, so a non-const [IconData] or
/// a `@staticIconProvider` annotation would sail through every widget test and
/// then either fail `flutter build apk --release` outright or ship blank
/// glyphs. They are source-level assertions on purpose.
void main() {
  const expectedCount = 49;

  group('library shape', () {
    test('holds exactly $expectedCount definitions', () {
      expect(MenuCategoryIcons.all, hasLength(expectedCount));
    });

    test('every key is unique', () {
      final keys = MenuCategoryIcons.all.map((d) => d.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('every glyph is distinct — no two keys render identically', () {
      // Two keys sharing a glyph would make the picker look broken (the owner
      // picks "salad", the grid highlights "meals" too).
      final icons = MenuCategoryIcons.all.map((d) => d.icon).toList();
      expect(icons.toSet(), hasLength(icons.length));
    });

    test('no key is empty and every key matches the wire format', () {
      // The same shape the Phase-2 `menu_categories.icon_key` CHECK enforces.
      final pattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final definition in MenuCategoryIcons.all) {
        expect(definition.key, isNotEmpty);
        expect(
          pattern.hasMatch(definition.key),
          isTrue,
          reason: '"${definition.key}" is not a legal icon key',
        );
      }
    });

    test('every definition belongs to a declared group and no group is '
        'empty', () {
      for (final definition in MenuCategoryIcons.all) {
        expect(MenuCategoryIconGroup.values, contains(definition.group));
      }
      for (final group in MenuCategoryIconGroup.values) {
        expect(
          MenuCategoryIcons.definitionsFor(group),
          isNotEmpty,
          reason: 'group ${group.name} would render as an empty picker section',
        );
      }
    });

    test('search tokens are lowercase, non-empty and free of whitespace', () {
      for (final definition in MenuCategoryIcons.all) {
        for (final token in definition.searchTokens) {
          expect(token, isNotEmpty);
          expect(token, equals(token.toLowerCase()));
          expect(token.contains(' '), isFalse, reason: 'token "$token"');
        }
      }
    });
  });

  group('picker order is contractual', () {
    test('definitions are grouped, in group declaration order', () {
      // The picker renders `all` top to bottom; a definition filed out of
      // order would appear under the wrong heading.
      var highWater = -1;
      final seen = <MenuCategoryIconGroup>{};
      for (final definition in MenuCategoryIcons.all) {
        final index = definition.group.index;
        if (index != highWater) {
          expect(
            seen.contains(definition.group),
            isFalse,
            reason: 'group ${definition.group.name} is split across the list',
          );
          expect(index, greaterThan(highWater));
          highWater = index;
          seen.add(definition.group);
        }
      }
      expect(seen, hasLength(MenuCategoryIconGroup.values.length));
    });

    test('definitionsFor preserves the order of `all`', () {
      final rebuilt = <MenuCategoryIconDefinition>[
        for (final group in MenuCategoryIconGroup.values)
          ...MenuCategoryIcons.definitionsFor(group),
      ];
      expect(
        rebuilt.map((d) => d.key).toList(),
        MenuCategoryIcons.all.map((d) => d.key).toList(),
      );
    });
  });

  group('lookup', () {
    test('a known key resolves to its glyph and its definition', () {
      expect(
        MenuCategoryIcons.iconForCategoryKey('burger'),
        Icons.lunch_dining,
      );
      expect(
        MenuCategoryIcons.definitionFor('burger')?.group,
        MenuCategoryIconGroup.fastFood,
      );
      expect(MenuCategoryIcons.isKnownCategoryIconKey('burger'), isTrue);
    });

    test(
      'null returns null — "no icon chosen" is not the registry\'s call',
      () {
        expect(MenuCategoryIcons.iconForCategoryKey(null), isNull);
        expect(MenuCategoryIcons.definitionFor(null), isNull);
        expect(MenuCategoryIcons.isKnownCategoryIconKey(null), isFalse);
      },
    );

    test('an unknown key from a NEWER dashboard degrades to null, never '
        'throws', () {
      // Forward compatibility: a newer picker must not blank out or crash an
      // older POS binary. The consuming surface keeps its own fallback.
      for (final unknown in <String>[
        '',
        'not_a_real_icon',
        'burger2',
        'BURGER',
      ]) {
        expect(
          MenuCategoryIcons.iconForCategoryKey(unknown),
          isNull,
          reason: 'key "$unknown"',
        );
        expect(
          MenuCategoryIcons.isKnownCategoryIconKey(unknown),
          isFalse,
          reason: 'key "$unknown"',
        );
      }
    });

    test('keys agrees with all', () {
      expect(
        MenuCategoryIcons.keys,
        MenuCategoryIcons.all.map((d) => d.key).toSet(),
      );
      expect(MenuCategoryIcons.keys, hasLength(expectedCount));
    });

    test('every definition is reachable by its own key', () {
      for (final definition in MenuCategoryIcons.all) {
        expect(
          MenuCategoryIcons.definitionFor(definition.key),
          same(definition),
        );
      }
    });
  });

  group('material-only, one family, no brands', () {
    test('every glyph comes from the bundled MaterialIcons font', () {
      for (final definition in MenuCategoryIcons.all) {
        expect(
          definition.icon.fontFamily,
          'MaterialIcons',
          reason: definition.key,
        );
        expect(definition.icon.fontPackage, isNull, reason: definition.key);
      }
    });

    test('no trademarked or brand glyph is in the allow-list', () {
      const brands = <IconData>[
        Icons.apple,
        Icons.facebook,
        Icons.android,
        Icons.reddit,
        Icons.telegram,
        Icons.discord,
        Icons.paypal,
      ];
      final chosen = MenuCategoryIcons.all.map((d) => d.icon).toSet();
      for (final brand in brands) {
        expect(
          chosen.contains(brand),
          isFalse,
          reason: 'brand glyph ${brand.codePoint} must not be pickable',
        );
      }
    });

    test('the set is strictly FILLED — no outlined/rounded/sharp variant', () {
      // A mixed-weight rail is the visual regression this ticket must avoid.
      // Variant glyphs live at distinct codepoints, so compare against them.
      const variants = <IconData>[
        Icons.restaurant_outlined,
        Icons.restaurant_rounded,
        Icons.restaurant_sharp,
        Icons.local_cafe_outlined,
        Icons.local_bar_outlined,
        Icons.water_drop_outlined,
        Icons.local_dining_outlined,
      ];
      final chosen = MenuCategoryIcons.all.map((d) => d.icon).toSet();
      for (final variant in variants) {
        expect(chosen.contains(variant), isFalse);
      }
    });
  });

  group('release safety (source-level — release-only failures)', () {
    late String source;

    setUpAll(() {
      source = _registrySource();
    });

    test('the registry constructs no IconData dynamically', () {
      // A non-const IconData makes `flutter build apk --release` fail with
      // "This application cannot tree shake icons fonts". Comments are
      // stripped first: the library doc quotes that very error message.
      final code = _withoutComments(source);
      expect(
        code.contains('IconData('),
        isFalse,
        reason:
            'the registry must reference const Icons.* only — a raw '
            'IconData(...) breaks the release build',
      );
    });

    test('the registry is NOT annotated @staticIconProvider', () {
      // That annotation tells the tree shaker to IGNORE these constants, which
      // would strip all $expectedCount glyphs from the release font and render
      // blanks in release only.
      expect(_withoutComments(source).contains('@staticIconProvider'), isFalse);
    });

    test('every icon is written as a const Icons.* reference', () {
      final code = _withoutComments(source);
      final referenced = RegExp(
        r'icon:\s*Icons\.([a-z0-9_]+)',
      ).allMatches(code).map((m) => m.group(1)).toSet();
      expect(referenced, hasLength(expectedCount));
    });
  });
}

/// Reads the registry's own source. Walks up from the test's working directory
/// so the file is found whether the suite runs from the package root or from
/// the repository root.
String _registrySource() {
  const relative = 'lib/src/menu_category_icons.dart';
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final candidate in <String>[
      '${dir.path}/$relative',
      '${dir.path}/packages/design_system/$relative',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file.readAsStringSync();
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate $relative from ${Directory.current.path}');
}

/// Strips `///`, `//` and `/* */` comments so a prose mention of a forbidden
/// pattern cannot fail the source assertions.
String _withoutComments(String source) {
  final withoutBlocks = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  return withoutBlocks
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

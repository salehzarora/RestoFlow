import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';

/// STOREFRONT-PUBLISH-001 — the OpeningHours model against the EXACT grammar of
/// `app.storefront_opening_hours_is_valid`: dow a JSON integer 0..6, HH:MM,
/// open != close, `closed: false` never a shape (never emitted), caps
/// 21 weekly / 62 exceptions, overnight windows allowed.
Map<String, Object?> _w(Object? dow, Object? open, Object? close) => {
  'dow': dow,
  'open': open,
  'close': close,
};

bool _valid(Object? json) => OpeningHours.isValidJson(json);

void main() {
  const sample = OpeningHours(
    weekly: [
      WeeklyWindow(dow: 0, open: '09:00', close: '15:00'),
      WeeklyWindow(dow: 0, open: '18:00', close: '23:30'),
      WeeklyWindow(dow: 5, open: '20:00', close: '02:00'), // overnight
      WeeklyWindow(dow: 6, open: '00:00', close: '23:59'),
    ],
    exceptions: [
      HoursException.closed('2026-10-02'),
      HoursException.window(date: '2026-12-31', open: '19:00', close: '03:00'),
    ],
  );

  group('round trip', () {
    test('toJson -> fromJson is lossless and valid', () {
      final json = sample.toJson();
      expect(_valid(json), isTrue);
      expect(OpeningHours.fromJson(json), sample);
      // Through real JSON text too (what the RPC transport does).
      final decoded = jsonDecode(jsonEncode(json));
      expect(OpeningHours.fromJson(decoded), sample);
      expect(sample.validate(), isEmpty);
      expect(sample.isValid, isTrue);
    });

    test('the wire shape is exact: both keys, exact entry keys', () {
      final json = sample.toJson();
      expect(json.keys.toList(), ['weekly', 'exceptions']);
      final weekly = json['weekly']! as List;
      expect((weekly.first as Map).keys.toSet(), {'dow', 'open', 'close'});
      expect((weekly.first as Map)['dow'], isA<int>());
      final exceptions = json['exceptions']! as List;
      expect(exceptions[0], {'date': '2026-10-02', 'closed': true});
      expect(exceptions[1], {
        'date': '2026-12-31',
        'open': '19:00',
        'close': '03:00',
      });
    });

    test('closed:false is NEVER emitted', () {
      final text = jsonEncode(sample.toJson());
      expect(text.contains('"closed":false'), isFalse);
      for (final e in sample.exceptions) {
        final j = e.toJson();
        if (!e.closed) expect(j.containsKey('closed'), isFalse);
        if (e.closed) {
          expect(j.containsKey('open') || j.containsKey('close'), isFalse);
        }
      }
    });

    test('the empty default round-trips (the writer default shape)', () {
      final json = OpeningHours.empty.toJson();
      expect(json, {'weekly': <Object>[], 'exceptions': <Object>[]});
      expect(_valid(json), isTrue);
      expect(OpeningHours.fromJson({}), OpeningHours.empty);
      expect(OpeningHours.fromJson({'weekly': <Object>[]}), OpeningHours.empty);
    });

    test('windowsFor groups by weekday (0 = Sunday)', () {
      expect(sample.windowsFor(0), hasLength(2));
      expect(sample.windowsFor(1), isEmpty);
      expect(sample.hasWeeklyWindow, isTrue);
      expect(OpeningHours.empty.hasWeeklyWindow, isFalse);
    });
  });

  group('the exact grammar (isValidJson)', () {
    test('top level: an object with only weekly / exceptions', () {
      expect(_valid(null), isFalse);
      expect(_valid(<Object>[]), isFalse);
      expect(_valid('{}'), isFalse);
      expect(_valid({'weekly': <Object>[], 'timezone': 'UTC'}), isFalse);
      expect(_valid({'weekly': <String, Object>{}}), isFalse);
      expect(_valid({'exceptions': 'none'}), isFalse);
    });

    test('dow is a JSON integer 0..6', () {
      for (final dow in [0, 1, 6]) {
        expect(
          _valid({
            'weekly': [_w(dow, '09:00', '10:00')],
          }),
          isTrue,
        );
      }
      for (final dow in [-1, 7, 1.5, '1', true, null]) {
        expect(
          _valid({
            'weekly': [_w(dow, '09:00', '10:00')],
          }),
          isFalse,
          reason: 'dow=$dow',
        );
      }
      // A JSON "1.0" decodes to a double (VM): the SQL regex ^[0-6]$ refuses
      // it too, so it is not accepted here.
      expect(
        _valid(
          jsonDecode('{"weekly":[{"dow":1.0,"open":"09:00","close":"10:00"}]}'),
        ),
        isFalse,
      );
    });

    test('HH:MM is exactly 00..23 : 00..59', () {
      for (final t in ['00:00', '09:05', '23:59', '12:30']) {
        expect(
          _valid({
            'weekly': [_w(1, t, '23:58')],
          }),
          isTrue,
          reason: t,
        );
      }
      for (final t in [
        '24:00',
        '9:00',
        '09:60',
        '09:00:00',
        '0900',
        '',
        ' 09:00',
      ]) {
        expect(
          _valid({
            'weekly': [_w(1, t, '10:00')],
          }),
          isFalse,
          reason: t,
        );
        expect(
          _valid({
            'weekly': [_w(1, '10:00', t)],
          }),
          isFalse,
          reason: t,
        );
      }
      expect(
        _valid({
          'weekly': [_w(1, 900, '10:00')],
        }),
        isFalse,
      );
    });

    test('open == close is refused (weekly and exceptions)', () {
      expect(
        _valid({
          'weekly': [_w(1, '10:00', '10:00')],
        }),
        isFalse,
      );
      expect(
        _valid({
          'exceptions': [
            {'date': '2026-10-01', 'open': '10:00', 'close': '10:00'},
          ],
        }),
        isFalse,
      );
    });

    test('overnight (close earlier than open) is allowed', () {
      expect(
        _valid({
          'weekly': [_w(5, '18:00', '02:00')],
        }),
        isTrue,
      );
      const w = WeeklyWindow(dow: 5, open: '18:00', close: '02:00');
      expect(w.crossesMidnight, isTrue);
      expect(
        const WeeklyWindow(
          dow: 5,
          open: '08:00',
          close: '17:00',
        ).crossesMidnight,
        isFalse,
      );
      expect(
        const HoursException.window(
          date: '2026-12-31',
          open: '22:00',
          close: '01:00',
        ).crossesMidnight,
        isTrue,
      );
      expect(
        const HoursException.closed('2026-12-31').crossesMidnight,
        isFalse,
      );
    });

    test('no extra keys, and (stricter than the SQL) no missing keys', () {
      expect(
        _valid({
          'weekly': [
            {..._w(1, '09:00', '10:00'), 'label': 'lunch'},
          ],
        }),
        isFalse,
      );
      expect(
        _valid({
          'weekly': [
            {'dow': 1, 'open': '09:00'},
          ],
        }),
        isFalse,
      );
      expect(
        _valid({
          'weekly': [<String, Object>{}],
        }),
        isFalse,
      );
      expect(
        _valid({
          'exceptions': [
            {'closed': true},
          ],
        }),
        isFalse,
      );
    });

    test('exceptions: {date, closed:true} or {date, open, close} only', () {
      expect(
        _valid({
          'exceptions': [
            {'date': '2026-10-01', 'closed': true},
          ],
        }),
        isTrue,
      );
      expect(
        _valid({
          'exceptions': [
            {'date': '2026-10-01', 'open': '09:00', 'close': '12:00'},
          ],
        }),
        isTrue,
      );
      final invalid = <Map<String, Object?>>[
        // closed:false is not a shape, with or without times
        {'date': '2026-10-01', 'closed': false},
        {
          'date': '2026-10-01',
          'closed': false,
          'open': '09:00',
          'close': '12:00',
        },
        {
          'date': '2026-10-01',
          'closed': null,
          'open': '09:00',
          'close': '12:00',
        },
        {'date': '2026-10-01', 'closed': 'true'},
        // closed with times
        {'date': '2026-10-01', 'closed': true, 'open': '09:00'},
        {'date': '2026-10-01', 'closed': true, 'close': '12:00'},
        // neither closed nor a full window
        {'date': '2026-10-01'},
        {'date': '2026-10-01', 'open': '09:00'},
        // extra key
        {'date': '2026-10-01', 'closed': true, 'note': 'holiday'},
      ];
      for (final e in invalid) {
        expect(
          _valid({
            'exceptions': [e],
          }),
          isFalse,
          reason: '$e',
        );
      }
    });

    test('date is YYYY-MM-DD in the server shape (shape only)', () {
      for (final d in ['2026-01-01', '2026-12-31', '2026-02-31']) {
        expect(
          _valid({
            'exceptions': [
              {'date': d, 'closed': true},
            ],
          }),
          isTrue,
          reason: d,
        );
      }
      for (final d in [
        '2026-13-01',
        '2026-00-10',
        '2026-1-01',
        '26-01-01',
        '2026-01-32',
        '2026/01/01',
      ]) {
        expect(
          _valid({
            'exceptions': [
              {'date': d, 'closed': true},
            ],
          }),
          isFalse,
          reason: d,
        );
      }
    });

    test('caps: <= 21 weekly windows, <= 62 exceptions', () {
      List<Map<String, Object?>> weekly(int n) => [
        for (var i = 0; i < n; i++) _w(i % 7, '0${i % 10}:00', '0${i % 10}:30'),
      ];
      List<Map<String, Object?>> exceptions(int n) => [
        for (var i = 0; i < n; i++)
          {
            'date':
                '2026-${(i ~/ 28 + 1).toString().padLeft(2, '0')}-'
                '${(i % 28 + 1).toString().padLeft(2, '0')}',
            'closed': true,
          },
      ];
      expect(_valid({'weekly': weekly(21)}), isTrue);
      expect(_valid({'weekly': weekly(22)}), isFalse);
      expect(_valid({'exceptions': exceptions(62)}), isTrue);
      expect(_valid({'exceptions': exceptions(63)}), isFalse);

      final tooManyWeekly = OpeningHours.fromJson({'weekly': weekly(21)});
      final grown = OpeningHours(
        weekly: [
          ...tooManyWeekly.weekly,
          const WeeklyWindow(dow: 1, open: '10:00', close: '11:00'),
        ],
      );
      expect(
        grown.validate(),
        contains(const OpeningHoursIssue(OpeningHoursIssueKind.tooManyWeekly)),
      );
      expect(_valid(grown.toJson()), isFalse);

      final manyExceptions = OpeningHours(
        exceptions: [
          for (var i = 0; i < 63; i++)
            const HoursException.closed('2026-10-01'),
        ],
      );
      expect(
        manyExceptions.validate(),
        contains(
          const OpeningHoursIssue(
            OpeningHoursIssueKind.tooManyExceptions,
            inExceptions: true,
          ),
        ),
      );
    });

    test('fromJson refuses anything outside the grammar (typed)', () {
      expect(
        () => OpeningHours.fromJson({
          'exceptions': [
            {'date': '2026-10-01', 'closed': false},
          ],
        }),
        throwsA(
          isA<StorefrontDecodeException>().having(
            (e) => e.field,
            'field',
            'opening_hours',
          ),
        ),
      );
      expect(
        () => OpeningHours.fromJson(null, path: 'profile.opening_hours'),
        throwsA(
          isA<StorefrontDecodeException>().having(
            (e) => e.field,
            'field',
            'profile.opening_hours',
          ),
        ),
      );
    });
  });

  group('validate() — the client-side mirror', () {
    test('reports each issue with its index', () {
      const hours = OpeningHours(
        weekly: [
          WeeklyWindow(dow: 7, open: '09:00', close: '10:00'),
          WeeklyWindow(dow: 1, open: '9:00', close: '10:00'),
          WeeklyWindow(dow: 2, open: '10:00', close: '10:00'),
          WeeklyWindow(dow: 3, open: '10:00', close: '11:00'),
        ],
        exceptions: [
          HoursException.closed('2026-13-01'),
          HoursException.window(
            date: '2026-10-01',
            open: '08:00',
            close: '08:00',
          ),
          HoursException.window(
            date: '2026-10-02',
            open: '08:00',
            close: '25:00',
          ),
        ],
      );
      expect(hours.validate(), [
        const OpeningHoursIssue(OpeningHoursIssueKind.dowOutOfRange, index: 0),
        const OpeningHoursIssue(OpeningHoursIssueKind.invalidTime, index: 1),
        const OpeningHoursIssue(
          OpeningHoursIssueKind.openEqualsClose,
          index: 2,
        ),
        const OpeningHoursIssue(
          OpeningHoursIssueKind.invalidDate,
          inExceptions: true,
          index: 0,
        ),
        const OpeningHoursIssue(
          OpeningHoursIssueKind.openEqualsClose,
          inExceptions: true,
          index: 1,
        ),
        const OpeningHoursIssue(
          OpeningHoursIssueKind.invalidTime,
          inExceptions: true,
          index: 2,
        ),
      ]);
      expect(hours.isValid, isFalse);
      // The mirror agrees with the grammar on what it emits.
      expect(_valid(hours.toJson()), isFalse);
    });

    test('validate() and isValidJson agree on every valid model', () {
      expect(_valid(sample.toJson()), sample.isValid);
      expect(_valid(OpeningHours.empty.toJson()), OpeningHours.empty.isValid);
    });

    test('grammar helpers', () {
      expect(isStorefrontHhmm('23:59'), isTrue);
      expect(isStorefrontHhmm('24:00'), isFalse);
      expect(isStorefrontDate('2026-10-01'), isTrue);
      expect(isStorefrontDate('2026-10-1'), isFalse);
      expect(OpeningHours.maxWindowsPerDay * 7, OpeningHours.maxWeekly);
    });
  });

  group('the STORED value (fromStored)', () {
    test('a value in the exact grammar decodes unflagged', () {
      final stored = OpeningHours.fromStored(sample.toJson());
      expect(stored, sample);
      expect(stored.hasUnreadableEntries, isFalse);
    });

    test('entries missing a key (the SQL check lets them through) are left '
        'out and FLAGGED — never a failed profile read', () {
      final stored = OpeningHours.fromStored({
        'weekly': [
          {'dow': 1, 'open': '09:00'},
          <String, Object?>{},
          _w(2, '10:00', '14:00'),
        ],
        'exceptions': [
          {'closed': true},
          {'date': '2026-10-01', 'open': '09:00'},
          {'date': '2026-10-02', 'closed': true},
        ],
      });
      expect(stored.hasUnreadableEntries, isTrue);
      expect(stored.weekly, const [
        WeeklyWindow(dow: 2, open: '10:00', close: '14:00'),
      ]);
      expect(stored.exceptions, const [HoursException.closed('2026-10-02')]);
      // What the editor builds is never equal to the flagged value (an edit
      // makes the draft dirty), and what a save writes is the exact grammar.
      final clean = OpeningHours(
        weekly: stored.weekly,
        exceptions: stored.exceptions,
      );
      expect(clean == stored, isFalse);
      expect(clean.hasUnreadableEntries, isFalse);
      expect(_valid(clean.toJson()), isTrue);
    });

    test('anything the database check itself refuses is still a typed '
        'decode failure', () {
      for (final bad in <Object?>[
        null,
        'x',
        {
          'weekly': [
            {'dow': 7},
          ],
        },
        {
          'weekly': [
            {'dow': null},
          ],
        },
        {
          'weekly': [
            {'dow': 1, 'open': '9:00'},
          ],
        },
        {
          'weekly': [
            {'open': '09:00', 'close': '09:00'},
          ],
        },
        {
          'weekly': [
            {'dow': 1, 'label': 'x'},
          ],
        },
        {
          'exceptions': [
            {'date': '2026-10-01', 'closed': false},
          ],
        },
        {
          'exceptions': [
            {'closed': true, 'open': '09:00'},
          ],
        },
        {
          'exceptions': [
            {'date': null},
          ],
        },
        {'other': <Object?>[]},
      ]) {
        expect(
          () => OpeningHours.fromStored(bad),
          throwsA(isA<StorefrontDecodeException>()),
          reason: '$bad',
        );
      }
    });

    test('C10 / OQ-1: the AUTHORITATIVE unreadable value is kept verbatim — '
        'never silently turned into empty/default hours', () {
      final raw = {
        'weekly': [<String, Object?>{}],
      };
      final stored = OpeningHours.fromStored(raw);
      expect(stored.hasUnreadableEntries, isTrue);
      expect(stored.weekly, isEmpty);
      expect(stored.storedRaw, raw);
      // Whatever serializes it answers the stored value, not `{"weekly":[],
      // "exceptions":[]}`.
      expect(stored.toJson(), raw);
      expect(stored.toJson(), isNot(OpeningHours.empty.toJson()));
      // A copy, not the caller's object.
      raw['weekly']!.add(<String, Object?>{'dow': 1});
      expect(stored.toJson(), {
        'weekly': [<String, Object?>{}],
      });
      // Equality follows the stored value; the explicit repair differs.
      expect(
        OpeningHours.fromStored({
          'weekly': [<String, Object?>{}],
        }),
        stored,
      );
      expect(
        OpeningHours.fromStored({
          'weekly': [
            {'dow': 3},
          ],
        }),
        isNot(stored),
      );
      final repaired = OpeningHours(
        weekly: stored.weekly,
        exceptions: stored.exceptions,
      );
      expect(repaired, isNot(stored));
      expect(repaired.storedRaw, isNull);
      expect(repaired.toJson(), OpeningHours.empty.toJson());
    });
  });

  group('overlaps() — ADVISORY (the server accepts every shape here)', () {
    OpeningHours hours(List<WeeklyWindow> weekly) =>
        OpeningHours(weekly: weekly);
    const w = WeeklyWindow.new;

    test('the sample: Friday\'s overnight window runs into Saturday', () {
      expect(sample.overlaps(), const [
        OpeningHoursOverlap(
          OpeningHoursOverlapKind.overnightSpill,
          dow: 5,
          index: 0,
          otherDow: 6,
          otherIndex: 0,
        ),
      ]);
    });

    test('duplicates and same-day overlaps (an overnight window counts to '
        'its end the next morning)', () {
      final h = hours(const [
        WeeklyWindow(dow: 1, open: '09:00', close: '17:00'),
        WeeklyWindow(dow: 1, open: '09:00', close: '17:00'),
        WeeklyWindow(dow: 2, open: '09:00', close: '12:00'),
        WeeklyWindow(dow: 2, open: '11:00', close: '15:00'),
        WeeklyWindow(dow: 3, open: '18:00', close: '02:00'),
        WeeklyWindow(dow: 3, open: '20:00', close: '23:00'),
      ]);
      expect(h.overlaps(), const [
        OpeningHoursOverlap(
          OpeningHoursOverlapKind.duplicate,
          dow: 1,
          index: 0,
          otherDow: 1,
          otherIndex: 1,
        ),
        OpeningHoursOverlap(
          OpeningHoursOverlapKind.sameDay,
          dow: 2,
          index: 0,
          otherDow: 2,
          otherIndex: 1,
        ),
        OpeningHoursOverlap(
          OpeningHoursOverlapKind.sameDay,
          dow: 3,
          index: 0,
          otherDow: 3,
          otherIndex: 1,
        ),
      ]);
      // Advisory: every one of these is valid for the server.
      expect(h.validate(), isEmpty);
      expect(OpeningHours.isValidJson(h.toJson()), isTrue);
    });

    test('Saturday runs into Sunday (the week wraps)', () {
      expect(
        hours([
          w(dow: 6, open: '22:00', close: '03:00'),
          w(dow: 0, open: '01:00', close: '10:00'),
        ]).overlaps(),
        const [
          OpeningHoursOverlap(
            OpeningHoursOverlapKind.overnightSpill,
            dow: 6,
            index: 0,
            otherDow: 0,
            otherIndex: 0,
          ),
        ],
      );
    });

    test('touching, separate, early-morning and invalid windows are not '
        'flagged as ADVISORY overlaps (touching is touchingWindows()\' '
        'blocking concern)', () {
      for (final weekly in [
        // touching (one ends when the other starts)
        [
          w(dow: 1, open: '09:00', close: '12:00'),
          w(dow: 1, open: '12:00', close: '15:00'),
        ],
        // an overnight end touching the next day's first window
        [
          w(dow: 5, open: '20:00', close: '02:00'),
          w(dow: 6, open: '02:00', close: '10:00'),
        ],
        // an early-morning window and the same day's overnight window
        [
          w(dow: 3, open: '22:00', close: '03:00'),
          w(dow: 3, open: '01:00', close: '02:00'),
        ],
        // a split shift
        [
          w(dow: 0, open: '08:00', close: '12:00'),
          w(dow: 0, open: '13:00', close: '17:00'),
          w(dow: 0, open: '18:00', close: '02:00'),
        ],
        // windows the validator refuses are validate()'s job
        [
          w(dow: 4, open: '09:00', close: '09:00'),
          w(dow: 4, open: '9:00', close: '17:00'),
          w(dow: 4, open: '10:00', close: '11:00'),
        ],
      ]) {
        expect(hours(weekly).overlaps(), isEmpty, reason: '$weekly');
      }
    });
  });

  group('touchingWindows() — Q-038: touching windows are BLOCKING', () {
    OpeningHours hours(List<WeeklyWindow> weekly) =>
        OpeningHours(weekly: weekly);
    const w = WeeklyWindow.new;
    OpeningHoursOverlap touch(int dow, int i, int otherDow, int j) =>
        OpeningHoursOverlap(
          OpeningHoursOverlapKind.touching,
          dow: dow,
          index: i,
          otherDow: otherDow,
          otherIndex: j,
        );

    test('09:00-12:00 + 12:00-23:00 touch (the reproduction)', () {
      final h = hours([
        w(dow: 1, open: '09:00', close: '12:00'),
        w(dow: 1, open: '12:00', close: '23:00'),
      ]);
      expect(h.touchingWindows(), [touch(1, 0, 1, 1)]);
      expect(h.hasTouchingWindows, isTrue);
      // The server validator accepts it, and it is not an advisory overlap:
      // only touchingWindows() refuses it.
      expect(h.isValid, isTrue);
      expect(OpeningHours.isValidJson(h.toJson()), isTrue);
      expect(h.overlaps(), isEmpty);
    });

    test('the order of the windows does not matter', () {
      final h = hours([
        w(dow: 1, open: '12:00', close: '23:00'),
        w(dow: 1, open: '09:00', close: '12:00'),
      ]);
      expect(h.touchingWindows(), [touch(1, 0, 1, 1)]);
    });

    test('09:00-12:00 + 12:01-23:00 do not touch; nor does a split shift', () {
      for (final weekly in [
        [
          w(dow: 1, open: '09:00', close: '12:00'),
          w(dow: 1, open: '12:01', close: '23:00'),
        ],
        [
          w(dow: 0, open: '08:00', close: '12:00'),
          w(dow: 0, open: '13:00', close: '17:00'),
          w(dow: 0, open: '18:00', close: '02:00'),
        ],
        // a true overlap stays the ADVISORY overlap it was
        [
          w(dow: 2, open: '09:00', close: '12:00'),
          w(dow: 2, open: '11:00', close: '23:00'),
        ],
      ]) {
        expect(hours(weekly).touchingWindows(), isEmpty, reason: '$weekly');
        expect(hours(weekly).hasTouchingWindows, isFalse, reason: '$weekly');
      }
      expect(
        hours([
          w(dow: 2, open: '09:00', close: '12:00'),
          w(dow: 2, open: '11:00', close: '23:00'),
        ]).overlaps().single.kind,
        OpeningHoursOverlapKind.sameDay,
      );
    });

    test('overnight boundaries: a window ending at midnight or past it '
        'touching the next weekday, Saturday into Sunday, and the same '
        "day's window ending when the overnight one opens", () {
      // Friday 20:00-02:00 + Saturday 02:00-10:00
      expect(
        hours([
          w(dow: 5, open: '20:00', close: '02:00'),
          w(dow: 6, open: '02:00', close: '10:00'),
        ]).touchingWindows(),
        [touch(5, 0, 6, 0)],
      );
      // Monday 18:00-00:00 + Tuesday 00:00-02:00 (a close of 00:00 is
      // midnight: the next weekday's window opening at 00:00 touches it)
      expect(
        hours([
          w(dow: 1, open: '18:00', close: '00:00'),
          w(dow: 2, open: '00:00', close: '02:00'),
        ]).touchingWindows(),
        [touch(1, 0, 2, 0)],
      );
      // Saturday 22:00-03:00 + Sunday 03:00-11:00 (the week wraps)
      expect(
        hours([
          w(dow: 6, open: '22:00', close: '03:00'),
          w(dow: 0, open: '03:00', close: '11:00'),
        ]).touchingWindows(),
        [touch(6, 0, 0, 0)],
      );
      // Wednesday 12:00-18:00 + Wednesday 18:00-02:00
      expect(
        hours([
          w(dow: 3, open: '12:00', close: '18:00'),
          w(dow: 3, open: '18:00', close: '02:00'),
        ]).touchingWindows(),
        [touch(3, 0, 3, 1)],
      );
      // A minute apart, or a spill into a later window, does not touch.
      for (final weekly in [
        [
          w(dow: 5, open: '20:00', close: '02:00'),
          w(dow: 6, open: '02:01', close: '10:00'),
        ],
        [
          w(dow: 1, open: '18:00', close: '23:59'),
          w(dow: 2, open: '00:00', close: '02:00'),
        ],
        // an overnight window and the SAME weekday's early window: the
        // overnight one ends on the next weekday
        [
          w(dow: 4, open: '20:00', close: '02:00'),
          w(dow: 4, open: '02:00', close: '06:00'),
        ],
      ]) {
        expect(hours(weekly).touchingWindows(), isEmpty, reason: '$weekly');
      }
    });

    test('windows the validator refuses are skipped', () {
      expect(
        hours([
          w(dow: 4, open: '09:00', close: '09:00'),
          w(dow: 4, open: '09:00', close: '12:00'),
          w(dow: 4, open: '9:00', close: '17:00'),
        ]).touchingWindows(),
        isEmpty,
      );
    });
  });

  group('suggestWindow() — "Add hours" never seeds a duplicate', () {
    OpeningHours day(List<(String, String)> windows) => OpeningHours(
      weekly: [
        for (final (o, c) in windows) WeeklyWindow(dow: 2, open: o, close: c),
      ],
    );

    test('an empty day gets 09:00-17:00', () {
      expect(
        OpeningHours.empty.suggestWindow(2),
        const WeeklyWindow(dow: 2, open: '09:00', close: '17:00'),
      );
    });

    test('after the day\'s latest close, else before its earliest open', () {
      final cases = <List<(String, String)>, WeeklyWindow>{
        [('09:00', '17:00')]: const WeeklyWindow(
          dow: 2,
          open: '18:00',
          close: '22:00',
        ),
        [('09:00', '17:00'), ('18:00', '22:00')]: const WeeklyWindow(
          dow: 2,
          open: '04:00',
          close: '08:00',
        ),
        [('18:00', '02:00')]: const WeeklyWindow(
          dow: 2,
          open: '13:00',
          close: '17:00',
        ),
        [('07:00', '21:30')]: const WeeklyWindow(
          dow: 2,
          open: '22:30',
          close: '23:59',
        ),
        [('00:00', '23:59')]: const WeeklyWindow(
          dow: 2,
          open: '09:00',
          close: '17:00',
        ),
      };
      for (final entry in cases.entries) {
        expect(day(entry.key).suggestWindow(2), entry.value, reason: '$entry');
      }
    });

    test('never an exact copy of an existing window of that day', () {
      for (final windows in [
        [('09:00', '17:00')],
        [('09:00', '17:00'), ('00:00', '23:59')],
        [('00:00', '23:59'), ('12:00', '15:00'), ('09:00', '17:00')],
        [('23:30', '23:45'), ('00:00', '00:30')],
      ]) {
        final h = day(windows);
        final s = h.suggestWindow(2);
        expect(h.windowsFor(2), isNot(contains(s)), reason: '$windows');
        expect(s.open == s.close, isFalse);
        expect(s.dow, 2);
      }
    });
  });
}

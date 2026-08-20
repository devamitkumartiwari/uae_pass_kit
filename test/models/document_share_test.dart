import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

void main() {
  group('UaePassDocumentShareRequest.toJson', () {
    test('matches the wire shape UaePassService.getUserDocumentDetails '
        'already sends today', () {
      final request = UaePassDocumentShareRequest(
        accessToken: 'token-1',
        emiratesId: '784-1990-1234567-1',
        uuid: 'uuid-1',
        documents: const [
          UaePassDocumentRequestItem(documentType: 'EmiratesId'),
          UaePassDocumentRequestItem(
            documentType: 'DrivingLicense',
            required: true,
          ),
        ],
        successUrl: Uri.parse('testapp://doc/success'),
        failureUrl: Uri.parse('testapp://doc/failure'),
        origin: UaePassDocumentShareOrigin.mobile,
      );

      final json = request.toJson();
      expect(json['authToken'], 'token-1');
      expect(json['emiratesId'], '784-1990-1234567-1');
      expect(json['uuId'], 'uuid-1');
      expect(json['origin'], 'MOBILE');
      expect(json['successUrl'], 'testapp://doc/success');
      expect(json['failureUrl'], 'testapp://doc/failure');
      expect(json['requestedDocuments'], [
        {'documentType': 'EmiratesId', 'required': false},
        {'documentType': 'DrivingLicense', 'required': true},
      ]);
    });

    test('origin.wireValue for web is WEB', () {
      expect(UaePassDocumentShareOrigin.web.wireValue, 'WEB');
    });
  });

  group('UaePassDocumentAuthorizationState.fromCode', () {
    test('maps every documented single-letter status code', () {
      expect(
        UaePassDocumentAuthorizationState.fromCode('Y'),
        UaePassDocumentAuthorizationState.authorized,
      );
      expect(
        UaePassDocumentAuthorizationState.fromCode('N'),
        UaePassDocumentAuthorizationState.rejected,
      );
      expect(
        UaePassDocumentAuthorizationState.fromCode('I'),
        UaePassDocumentAuthorizationState.invalid,
      );
      expect(
        UaePassDocumentAuthorizationState.fromCode('P'),
        UaePassDocumentAuthorizationState.pending,
      );
      expect(
        UaePassDocumentAuthorizationState.fromCode(null),
        UaePassDocumentAuthorizationState.unknown,
      );
    });

    test('only pending is non-terminal', () {
      expect(UaePassDocumentAuthorizationState.pending.isTerminal, isFalse);
      for (final state in [
        UaePassDocumentAuthorizationState.authorized,
        UaePassDocumentAuthorizationState.rejected,
        UaePassDocumentAuthorizationState.invalid,
        UaePassDocumentAuthorizationState.unknown,
      ]) {
        expect(state.isTerminal, isTrue, reason: '$state should be terminal');
      }
    });
  });

  group('UaePassDocumentShareItem.fromJson', () {
    test('parses status and a Z-suffixed expiry timestamp', () {
      final item = UaePassDocumentShareItem.fromJson({
        'documentType': 'EmiratesId',
        'reqAuthorized': 'P',
        'NotificationExpiry': '2020-01-01 00:00:00',
      });
      expect(item.state, UaePassDocumentAuthorizationState.pending);
      expect(item.notificationExpiry, isNotNull);
      expect(item.isExpired, isTrue);
    });

    test('has no expiry when NotificationExpiry is absent', () {
      final item = UaePassDocumentShareItem.fromJson({
        'documentType': 'EmiratesId',
        'reqAuthorized': 'Y',
      });
      expect(item.notificationExpiry, isNull);
      expect(item.isExpired, isFalse);
    });
  });
}

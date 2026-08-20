import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

void main() {
  group('UaePassSigningRequest.toProcessJson', () {
    test('serializes the signer/field/location/appearance tree matching '
        'the decompiled DocumentSigningRequestParams shape', () {
      final request = UaePassSigningRequest(
        documentBytes: Uint8List.fromList([1, 2, 3]),
        documentFileName: 'agreement.pdf',
        finishCallbackUrl: Uri.parse('testapp://sign/finish'),
        uiLocales: 'ar',
        signer: const UaePassSigner(
          fields: [
            UaePassSignatureField(
              name: 'signer1',
              pageNumber: 1,
              rectangle: UaePassSignatureRectangle(
                x: 10,
                y: 20,
                width: 150,
                height: 60,
              ),
              appearanceDetails: [
                UaePassSignatureAppearanceDetail(
                  type: 'signerName',
                  title: 'Signed by',
                ),
              ],
              showCardHolderSignatureImage: true,
            ),
          ],
        ),
      );

      final json = request.toProcessJson();
      expect(json['processType'], kUaePassSignProcessType);
      expect(json['finishCallbackUrl'], 'testapp://sign/finish');
      expect(json['uiLocales'], 'ar');

      final signer = json['signer'] as Map<String, dynamic>;
      expect(signer['signaturePolicyId'], kUaePassSignPolicyId);
      final parameters = signer['parameters'] as Map<String, dynamic>;
      expect(parameters['type'], 'pades-baseline');
      final fields = parameters['signatureField'] as List;
      expect(fields, hasLength(1));

      final field = fields.single as Map<String, dynamic>;
      expect(field['name'], 'signer1');
      final location = field['location'] as Map<String, dynamic>;
      expect((location['page'] as Map)['number'], 1);
      final rect = location['rectangle'] as Map<String, dynamic>;
      expect(rect, {'x': 10.0, 'y': 20.0, 'width': 150.0, 'height': 60.0});

      final appearance = field['appearance'] as Map<String, dynamic>;
      expect(appearance['showCardHolderSignatureImage'], isTrue);
      final details = appearance['signatureDetails'] as List;
      expect(details.single, {'type': 'signerName', 'title': 'Signed by'});
    });

    test('omits appearance entirely when there is nothing to show', () {
      final request = UaePassSigningRequest(
        documentBytes: Uint8List.fromList([1]),
        documentFileName: 'doc.pdf',
        finishCallbackUrl: Uri.parse('testapp://sign/finish'),
        signer: const UaePassSigner(
          fields: [
            UaePassSignatureField(
              name: 'signer1',
              pageNumber: 1,
              rectangle: UaePassSignatureRectangle(
                x: 0,
                y: 0,
                width: 1,
                height: 1,
              ),
            ),
          ],
        ),
      );
      final field =
          (((request.toProcessJson()['signer']
                              as Map<String, dynamic>)['parameters']
                          as Map<String, dynamic>)['signatureField']
                      as List)
                  .single
              as Map<String, dynamic>;
      expect(field.containsKey('appearance'), isFalse);
    });
  });

  group('UaePassSigningProcess.fromJson', () {
    test('parses pending tasks and documents from the decompiled '
        'DocSignatureProcessModel shape', () {
      final process = UaePassSigningProcess.fromJson({
        'id': 'process-1',
        'Tasks': {
          'pending': [
            {
              'type': 'sign',
              'id': 'task-1',
              'url': 'https://stg-id.uaepass.ae/esignsp/v2/ui?id=1',
            },
          ],
        },
        'documents': [
          {'url': 'https://stg-id.uaepass.ae/esignsp/v2/documents/doc-1'},
        ],
      });

      expect(process.id, 'process-1');
      expect(process.pendingTasks, hasLength(1));
      expect(process.pendingTasks.single.id, 'task-1');
      expect(process.signingUiUrl, process.pendingTasks.single.url);
      expect(process.documents, hasLength(1));
    });

    test('signingUiUrl is null once there are no pending tasks', () {
      final process = UaePassSigningProcess.fromJson({
        'id': 'process-1',
        'Tasks': <String, dynamic>{'pending': <dynamic>[]},
        'documents': <dynamic>[],
      });
      expect(process.signingUiUrl, isNull);
    });
  });

  group('UaePassSigningOutcome.fromStatusParam', () {
    test('finished and success both mean finished', () {
      expect(
        UaePassSigningOutcome.fromStatusParam('finished'),
        UaePassSigningOutcome.finished,
      );
      expect(
        UaePassSigningOutcome.fromStatusParam('success'),
        UaePassSigningOutcome.finished,
      );
    });

    test('anything else, including null, means cancelled', () {
      expect(
        UaePassSigningOutcome.fromStatusParam(null),
        UaePassSigningOutcome.cancelled,
      );
      expect(
        UaePassSigningOutcome.fromStatusParam('declined'),
        UaePassSigningOutcome.cancelled,
      );
    });
  });
}

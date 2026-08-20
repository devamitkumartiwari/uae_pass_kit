import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

Map<String, dynamic> _loadFixture(String name) {
  final content = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(content) as Map<String, dynamic>;
}

void main() {
  group('UaePassProfile.fromJson', () {
    test('parses every field of the full 37-field union fixture', () {
      final profile = UaePassProfile.fromJson(
        _loadFixture('profile_full.json'),
      );

      expect(profile.sub, 'sub-0001');
      expect(profile.uuid, 'uuid-0001');
      expect(profile.spuuid, 'spuuid-0001');
      expect(profile.emiratesId, '784-1990-1234567-1');
      expect(profile.idType, 'EmiratesId');
      expect(profile.userType, 'Citizen');
      expect(profile.profileType, 'Individual');
      expect(profile.domain, 'UAEPASS');
      expect(profile.acr, 'urn:digitalid:authentication:flow:mobileondevice');
      expect(profile.amr, ['fingerprint', 'pin']);
      expect(profile.fullNameEn, 'Mohammed Ahmed Al Suwaidi');
      expect(profile.fullNameAr, 'محمد أحمد السويدي');
      expect(profile.firstNameEn, 'Mohammed');
      expect(profile.firstNameAr, 'محمد');
      expect(profile.lastNameEn, 'Al Suwaidi');
      expect(profile.lastNameAr, 'السويدي');
      expect(profile.titleEn, 'Mr');
      expect(profile.titleAr, 'السيد');
      expect(profile.nationalityEn, 'United Arab Emirates');
      expect(profile.nationalityAr, 'الإمارات العربية المتحدة');
      expect(profile.gender, 'M');
      expect(profile.dateOfBirth, '1990-05-12');
      expect(profile.email, 'mohammed@example.com');
      expect(profile.mobile, '+971501234567');
      expect(profile.photoBase64, 'base64-photo-data');
      expect(profile.passportNumber, 'N1234567');
      expect(profile.cardHolderSignatureImageBase64, 'base64-signature-data');

      final address = profile.homeAddress;
      expect(address, isNotNull);
      expect(address!.areaCode, 'AREA01');
      expect(address.areaDescriptionEn, 'Al Barsha');
      expect(address.areaDescriptionAr, 'البرشاء');
      expect(address.cityCode, 'CITY01');
      expect(address.cityDescriptionEn, 'Dubai');
      expect(address.emirateCode, 'EMIRATE01');
      expect(address.typeCode, 'RESIDENTIAL');
      expect(address.poBox, '12345');
      expect(address.mobilePhoneNumber, '+971501234567');
    });

    test('never throws on a minimal profile — every field is nullable', () {
      final profile = UaePassProfile.fromJson(
        _loadFixture('profile_minimal.json'),
      );
      expect(profile.sub, 'sub-0002');
      expect(profile.fullNameEn, 'Visitor Profile');
      expect(profile.emiratesId, isNull);
      expect(profile.homeAddress, isNull);
      expect(profile.amr, isEmpty);
    });

    test('preserves the raw JSON for forward-compatibility', () {
      final json = _loadFixture('profile_full.json');
      final profile = UaePassProfile.fromJson(json);
      expect(profile.raw, json);
    });

    test('round-trips through toJson without losing the address fields', () {
      final original = _loadFixture('profile_full.json');
      final profile = UaePassProfile.fromJson(original);
      final roundTripped = UaePassProfile.fromJson(profile.toJson());

      expect(roundTripped.emiratesId, profile.emiratesId);
      expect(
        roundTripped.homeAddress?.cityDescriptionEn,
        profile.homeAddress?.cityDescriptionEn,
      );
      expect(roundTripped.fullNameAr, profile.fullNameAr);
    });
  });
}

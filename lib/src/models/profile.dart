/// The authenticated user's home address, as returned by UAE Pass for
/// citizen/resident profiles.
///
/// UAE Pass's own iOS SDK model omits this decomposition entirely (it only
/// appears in the Android SDK's `ProfileModel`) even though both SDKs call
/// the same `/idshub/userinfo` endpoint — this plugin parses the full set
/// regardless of platform so no field is silently dropped.
class UaePassHomeAddress {
  /// Creates a home address value object.
  const UaePassHomeAddress({
    this.areaCode,
    this.areaDescriptionEn,
    this.areaDescriptionAr,
    this.cityCode,
    this.cityDescriptionEn,
    this.cityDescriptionAr,
    this.emirateCode,
    this.emirateDescriptionEn,
    this.emirateDescriptionAr,
    this.typeCode,
    this.poBox,
    this.mobilePhoneNumber,
  });

  /// Parses a [UaePassHomeAddress] from the flat top-level userinfo JSON
  /// [json], or returns `null` if none of the `homeAddress*` keys are
  /// present.
  static UaePassHomeAddress? fromUserInfoJson(Map<String, dynamic> json) {
    const homeAddressKeys = [
      'homeAddressAreaCode',
      'homeAddressAreaDescriptionEN',
      'homeAddressAreaDescriptionAR',
      'homeAddressCityCode',
      'homeAddressCityDescriptionEN',
      'homeAddressCityDescriptionAR',
      'homeAddressEmirateCode',
      'homeAddressEmirateDescriptionEN',
      'homeAddressEmirateDescriptionAR',
      'homeAddressTypeCode',
      'homeAddressPOBox',
      'homeAddressMobilePhoneNumber',
    ];
    final hasAddress = homeAddressKeys.any((key) => json[key] != null);
    if (!hasAddress) return null;

    return UaePassHomeAddress(
      areaCode: json['homeAddressAreaCode'] as String?,
      areaDescriptionEn: json['homeAddressAreaDescriptionEN'] as String?,
      areaDescriptionAr: json['homeAddressAreaDescriptionAR'] as String?,
      cityCode: json['homeAddressCityCode'] as String?,
      cityDescriptionEn: json['homeAddressCityDescriptionEN'] as String?,
      cityDescriptionAr: json['homeAddressCityDescriptionAR'] as String?,
      emirateCode: json['homeAddressEmirateCode'] as String?,
      emirateDescriptionEn: json['homeAddressEmirateDescriptionEN'] as String?,
      emirateDescriptionAr: json['homeAddressEmirateDescriptionAR'] as String?,
      typeCode: json['homeAddressTypeCode'] as String?,
      poBox: json['homeAddressPOBox'] as String?,
      mobilePhoneNumber: json['homeAddressMobilePhoneNumber'] as String?,
    );
  }

  /// Area code.
  final String? areaCode;

  /// Area description in English.
  final String? areaDescriptionEn;

  /// Area description in Arabic.
  final String? areaDescriptionAr;

  /// City code.
  final String? cityCode;

  /// City description in English.
  final String? cityDescriptionEn;

  /// City description in Arabic.
  final String? cityDescriptionAr;

  /// Emirate code.
  final String? emirateCode;

  /// Emirate description in English.
  final String? emirateDescriptionEn;

  /// Emirate description in Arabic.
  final String? emirateDescriptionAr;

  /// Address type code.
  final String? typeCode;

  /// PO Box.
  final String? poBox;

  /// Mobile phone number associated with the home address record.
  final String? mobilePhoneNumber;

  /// Flattens this address back into the `homeAddress*` keys UAE Pass uses.
  Map<String, dynamic> toUserInfoJson() => {
    'homeAddressAreaCode': areaCode,
    'homeAddressAreaDescriptionEN': areaDescriptionEn,
    'homeAddressAreaDescriptionAR': areaDescriptionAr,
    'homeAddressCityCode': cityCode,
    'homeAddressCityDescriptionEN': cityDescriptionEn,
    'homeAddressCityDescriptionAR': cityDescriptionAr,
    'homeAddressEmirateCode': emirateCode,
    'homeAddressEmirateDescriptionEN': emirateDescriptionEn,
    'homeAddressEmirateDescriptionAR': emirateDescriptionAr,
    'homeAddressTypeCode': typeCode,
    'homeAddressPOBox': poBox,
    'homeAddressMobilePhoneNumber': mobilePhoneNumber,
  };
}

/// The authenticated user's UAE Pass profile, as returned by
/// `GET /idshub/userinfo`.
///
/// Field set mirrors the full union found by decompiling the real official
/// Android SDK's `ProfileModel` (37 fields) plus `profileType`, documented
/// separately on docs.uaepass.ae — a superset of both official native
/// SDKs' own (narrower, and mutually different) model classes. Exactly
/// which fields are actually populated for a given user depends on the
/// requested `scope` and the user's profile type, so every field here is
/// nullable by design; this plugin never assumes a field is present.
class UaePassProfile {
  /// Creates a UAE Pass profile. Prefer [UaePassProfile.fromJson] when
  /// parsing a UAE Pass response.
  const UaePassProfile({
    this.sub,
    this.uuid,
    this.spuuid,
    this.emiratesId,
    this.idType,
    this.userType,
    this.profileType,
    this.domain,
    this.acr,
    this.amr = const [],
    this.fullNameEn,
    this.fullNameAr,
    this.firstNameEn,
    this.firstNameAr,
    this.lastNameEn,
    this.lastNameAr,
    this.titleEn,
    this.titleAr,
    this.nationalityEn,
    this.nationalityAr,
    this.gender,
    this.dateOfBirth,
    this.email,
    this.mobile,
    this.photoBase64,
    this.passportNumber,
    this.cardHolderSignatureImageBase64,
    this.homeAddress,
    this.raw = const {},
  });

  /// Parses a [UaePassProfile] from the raw JSON body returned by
  /// `/idshub/userinfo`. Unknown/extra fields are preserved in [raw] rather
  /// than discarded, so callers can still reach anything this model
  /// doesn't explicitly surface.
  factory UaePassProfile.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList(growable: false);
      }
      if (value is String && value.isNotEmpty) return [value];
      return const [];
    }

    return UaePassProfile(
      sub: json['sub'] as String?,
      uuid: json['uuid'] as String?,
      spuuid: json['spuuid'] as String?,
      emiratesId: json['idn'] as String?,
      idType: json['idType'] as String?,
      userType: json['userType'] as String?,
      profileType: json['profileType'] as String?,
      domain: json['domain'] as String?,
      acr: json['acr'] as String?,
      amr: stringList(json['amr']),
      fullNameEn: json['fullnameEN'] as String?,
      fullNameAr: json['fullnameAR'] as String?,
      firstNameEn: json['firstnameEN'] as String?,
      firstNameAr: json['firstnameAR'] as String?,
      lastNameEn: json['lastnameEN'] as String?,
      lastNameAr: json['lastnameAR'] as String?,
      titleEn: json['titleEN'] as String?,
      titleAr: json['titleAR'] as String?,
      nationalityEn: json['nationalityEN'] as String?,
      nationalityAr: json['nationalityAR'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: json['dob'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      photoBase64: json['photo'] as String?,
      passportNumber: json['passportNumber'] as String?,
      cardHolderSignatureImageBase64:
          json['cardHolderSignatureImage'] as String?,
      homeAddress: UaePassHomeAddress.fromUserInfoJson(json),
      raw: json,
    );
  }

  /// The OIDC subject identifier.
  final String? sub;

  /// UAE Pass unique user identifier.
  final String? uuid;

  /// Service-provider-scoped unique user identifier.
  final String? spuuid;

  /// The Emirates ID number (`idn` on the wire). Only present for
  /// citizen/resident profiles.
  final String? emiratesId;

  /// The type of ID the profile is based on.
  final String? idType;

  /// The UAE Pass user type classification.
  final String? userType;

  /// The UAE Pass profile type classification
  /// (`urn:uae:digitalid:profile:general:profileType` sub-scope).
  final String? profileType;

  /// The identity domain the user authenticated against.
  final String? domain;

  /// Authentication Context Class Reference — the authentication method
  /// strength actually used.
  final String? acr;

  /// Authentication Methods References — the specific methods used.
  final List<String> amr;

  /// Full name in English.
  final String? fullNameEn;

  /// Full name in Arabic.
  final String? fullNameAr;

  /// First name in English.
  final String? firstNameEn;

  /// First name in Arabic.
  final String? firstNameAr;

  /// Last name in English.
  final String? lastNameEn;

  /// Last name in Arabic.
  final String? lastNameAr;

  /// Honorific title in English.
  final String? titleEn;

  /// Honorific title in Arabic.
  final String? titleAr;

  /// Nationality in English.
  final String? nationalityEn;

  /// Nationality in Arabic.
  final String? nationalityAr;

  /// Gender, as reported by UAE Pass.
  final String? gender;

  /// Date of birth, as reported by UAE Pass (format is UAE Pass's own, not
  /// normalized by this plugin — parse defensively).
  final String? dateOfBirth;

  /// Email address.
  final String? email;

  /// Mobile number.
  final String? mobile;

  /// Base64-encoded profile photo, if shared.
  final String? photoBase64;

  /// Passport number, if shared.
  final String? passportNumber;

  /// Base64-encoded image of the Emirates ID card holder's signature, if
  /// shared. Embedding this in a signed document is subject to ICP
  /// approval — see the e-signature API.
  final String? cardHolderSignatureImageBase64;

  /// The user's decomposed home address, if present in the response.
  final UaePassHomeAddress? homeAddress;

  /// The complete, unmodified JSON body this profile was parsed from, for
  /// forward-compatibility with fields UAE Pass adds that this model
  /// doesn't yet name explicitly.
  final Map<String, dynamic> raw;

  /// Serializes this profile back to UAE Pass's wire format.
  Map<String, dynamic> toJson() => {
    'sub': sub,
    'uuid': uuid,
    'spuuid': spuuid,
    'idn': emiratesId,
    'idType': idType,
    'userType': userType,
    'profileType': profileType,
    'domain': domain,
    'acr': acr,
    'amr': amr,
    'fullnameEN': fullNameEn,
    'fullnameAR': fullNameAr,
    'firstnameEN': firstNameEn,
    'firstnameAR': firstNameAr,
    'lastnameEN': lastNameEn,
    'lastnameAR': lastNameAr,
    'titleEN': titleEn,
    'titleAR': titleAr,
    'nationalityEN': nationalityEn,
    'nationalityAR': nationalityAr,
    'gender': gender,
    'dob': dateOfBirth,
    'email': email,
    'mobile': mobile,
    'photo': photoBase64,
    'passportNumber': passportNumber,
    'cardHolderSignatureImage': cardHolderSignatureImageBase64,
    if (homeAddress != null) ...homeAddress!.toUserInfoJson(),
  };
}

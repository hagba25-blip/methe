class Profile {
  const Profile({
    required this.id,
    required this.publicId,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.countryCode,
    required this.languageCode,
    required this.currencyCode,
    required this.currencyDecimals,
    required this.avatarUrl,
    required this.status,
    required this.balance,
    required this.isStaff,
    required this.createdAt,
  });

  final String id;
  final String publicId;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final String countryCode;
  final String languageCode;
  final String currencyCode;
  final int currencyDecimals;
  final String? avatarUrl;
  final String status;
  final int balance; // unités mineures — affichage uniquement, calculé côté serveur
  final bool isStaff;
  final DateTime createdAt;

  String get fullName => '$firstName $lastName';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        publicId: j['public_id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        phone: j['phone'] as String,
        email: j['email'] as String?,
        countryCode: j['country_code'] as String,
        languageCode: j['language_code'] as String,
        currencyCode: j['currency_code'] as String,
        currencyDecimals: j['currency_decimals'] as int,
        avatarUrl: j['avatar_url'] as String?,
        status: j['status'] as String,
        balance: j['balance'] as int,
        isStaff: j['is_staff'] as bool,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

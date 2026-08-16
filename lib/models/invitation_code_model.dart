import 'package:hive/hive.dart';

part 'invitation_code_model.g.dart';

/// Model für einen Einladungscode.
@HiveType(typeId: 10)
class InvitationCode extends HiveObject {
  @HiveField(0)
  final String code;

  @HiveField(1)
  final DateTime createdAt;

  @HiveField(2)
  final String? usedBy;

  @HiveField(3)
  final DateTime? usedAt;

  @HiveField(4)
  final String? createdBy;

  @HiveField(5)
  final DateTime? expiresAt;

  @HiveField(6)
  final int maxUses;

  @HiveField(7)
  final int currentUses;

  InvitationCode({
    required this.code,
    required this.createdAt,
    this.usedBy,
    this.usedAt,
    this.createdBy,
    this.expiresAt,
    this.maxUses = 1,
    this.currentUses = 0,
  });

  /// Ob der Code noch gültig und einlösbar ist.
  bool get isValid {
    if (currentUses >= maxUses) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return false;
    return true;
  }

  /// Ob der Code bereits vollständig verbraucht ist.
  bool get isFullyUsed => currentUses >= maxUses;

  InvitationCode copyWith({
    String? code,
    DateTime? createdAt,
    String? usedBy,
    DateTime? usedAt,
    String? createdBy,
    DateTime? expiresAt,
    int? maxUses,
    int? currentUses,
  }) {
    return InvitationCode(
      code: code ?? this.code,
      createdAt: createdAt ?? this.createdAt,
      usedBy: usedBy ?? this.usedBy,
      usedAt: usedAt ?? this.usedAt,
      createdBy: createdBy ?? this.createdBy,
      expiresAt: expiresAt ?? this.expiresAt,
      maxUses: maxUses ?? this.maxUses,
      currentUses: currentUses ?? this.currentUses,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'createdAt': createdAt.toIso8601String(),
        'usedBy': usedBy,
        'usedAt': usedAt?.toIso8601String(),
        'createdBy': createdBy,
        'expiresAt': expiresAt?.toIso8601String(),
        'maxUses': maxUses,
        'currentUses': currentUses,
      };

  factory InvitationCode.fromJson(Map<String, dynamic> json) {
    return InvitationCode(
      code: json['code'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      usedBy: json['usedBy'] as String?,
      usedAt: json['usedAt'] == null ? null : DateTime.parse(json['usedAt'] as String),
      createdBy: json['createdBy'] as String?,
      expiresAt: json['expiresAt'] == null ? null : DateTime.parse(json['expiresAt'] as String),
      maxUses: json['maxUses'] as int? ?? 1,
      currentUses: json['currentUses'] as int? ?? 0,
    );
  }
}
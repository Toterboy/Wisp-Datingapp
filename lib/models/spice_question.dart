/// Eine Eisbrecher-Frage ("Spice Question") samt Antwort-Status.
///
/// Die Antwort des Partners wird erst sichtbar, wenn BEIDE geantwortet
/// haben ([answeredByBoth]) — serverseitig erzwungen (Migration 039).
class SpiceQuestion {
  const SpiceQuestion({
    required this.questionId,
    required this.prompt,
    required this.category,
    required this.answeredByMe,
    required this.answeredByPartner,
    this.myAnswer,
    this.partnerAnswer,
  });

  final int questionId;
  final String prompt;
  final String category;
  final bool answeredByMe;
  final bool answeredByPartner;
  final String? myAnswer;

  /// Nur gesetzt, wenn beide geantwortet haben (Server-Aufdeckung).
  final String? partnerAnswer;

  bool get answeredByBoth => answeredByMe && answeredByPartner;

  factory SpiceQuestion.fromJson(Map<String, dynamic> json) {
    return SpiceQuestion(
      questionId: (json['questionId'] as num).toInt(),
      prompt: json['prompt'] as String? ?? '',
      category: json['category'] as String? ?? 'icebreaker',
      answeredByMe: json['answeredByMe'] as bool? ?? false,
      answeredByPartner: json['answeredByPartner'] as bool? ?? false,
      myAnswer: json['myAnswer'] as String?,
      partnerAnswer: json['partnerAnswer'] as String?,
    );
  }
}

/// Ergebnis einer Antwort-Abgabe.
class SpiceAnswerResult {
  const SpiceAnswerResult({
    required this.questionId,
    required this.bothAnswered,
    this.partnerAnswer,
  });

  final int questionId;
  final bool bothAnswered;

  /// Partner-Antwort, sobald beide geantwortet haben (sonst null).
  final String? partnerAnswer;

  factory SpiceAnswerResult.fromJson(Map<String, dynamic> json) {
    return SpiceAnswerResult(
      questionId: (json['questionId'] as num).toInt(),
      bothAnswered: json['bothAnswered'] as bool? ?? false,
      partnerAnswer: json['partnerAnswer'] as String?,
    );
  }
}
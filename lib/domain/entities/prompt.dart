import 'package:equatable/equatable.dart';

class Prompt extends Equatable {
  final String id;
  final String gujaratiText;
  final String? transliteration;
  final String? category;
  final String? difficulty;
  final bool activeStatus;
  final DateTime? createdAt;

  const Prompt({
    required this.id,
    required this.gujaratiText,
    this.transliteration,
    this.category,
    this.difficulty,
    this.activeStatus = true,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        gujaratiText,
        transliteration,
        category,
        difficulty,
        activeStatus,
        createdAt,
      ];
}

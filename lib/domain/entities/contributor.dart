import 'package:equatable/equatable.dart';

class Contributor extends Equatable {
  final String id;
  final String? name;
  final String ageGroup;
  final String nativeRegion;
  final String currentRegion;
  final String dialect;
  final bool consentGiven;
  final DateTime? createdAt;

  const Contributor({
    required this.id,
    this.name,
    required this.ageGroup,
    required this.nativeRegion,
    required this.currentRegion,
    required this.dialect,
    required this.consentGiven,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        ageGroup,
        nativeRegion,
        currentRegion,
        dialect,
        consentGiven,
        createdAt,
      ];
}

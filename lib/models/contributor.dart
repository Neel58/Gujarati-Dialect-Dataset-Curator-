class Contributor {
  final String id;
  final String name;
  final int age;
  final String place;
  final String dialect;

  Contributor({
    required this.id,
    required this.name,
    required this.age,
    required this.place,
    required this.dialect,
  });

  factory Contributor.fromJson(Map<String, dynamic> json) {
    return Contributor(
      id: json['id'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      place: json['place'] as String,
      dialect: json['dialect'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'age': age,
    'place': place,
    'dialect': dialect,
  };
}

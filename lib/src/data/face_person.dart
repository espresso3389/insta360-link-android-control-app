import "package:isar/isar.dart";

part "face_person.g.dart";

@collection
class FacePerson {
  Id id = Isar.autoIncrement;

  late String name;

  DateTime createdAt = DateTime.now();

  List<byte>? faceJpegBytes;
  List<double>? faceEmbedding;

  double? boxX;
  double? boxY;
  double? boxW;
  double? boxH;
}

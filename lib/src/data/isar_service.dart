import "package:isar/isar.dart";
import "package:path_provider/path_provider.dart";

import "app_settings.dart";
import "face_person.dart";

class IsarService {
  IsarService._(this.isar);

  final Isar isar;

  static IsarService? _instance;

  static Future<IsarService> getInstance() async {
    if (_instance != null) {
      return _instance!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [FacePersonSchema, AppSettingsSchema],
      directory: dir.path,
    );
    _instance = IsarService._(isar);
    return _instance!;
  }

  Future<List<FacePerson>> listPeople() async {
    return isar.facePersons.where().sortByCreatedAtDesc().findAll();
  }

  Future<List<FacePerson>> listPeopleByName(String name) async {
    return isar.facePersons
        .filter()
        .nameEqualTo(name)
        .sortByCreatedAtDesc()
        .findAll();
  }

  Future<FacePerson> upsertPerson(FacePerson person) async {
    await isar.writeTxn(() async {
      await isar.facePersons.put(person);
    });
    return person;
  }

  Future<void> deletePerson(Id id) async {
    await isar.writeTxn(() async {
      await isar.facePersons.delete(id);
    });
  }

  Future<void> deletePeopleByName(String name) async {
    await isar.writeTxn(() async {
      final people = await isar.facePersons
          .filter()
          .nameEqualTo(name)
          .findAll();
      final ids = people.map((FacePerson p) => p.id).toList();
      await isar.facePersons.deleteAll(ids);
    });
  }

  Future<void> renamePeople(String fromName, String toName) async {
    await isar.writeTxn(() async {
      final people = await isar.facePersons
          .filter()
          .nameEqualTo(fromName)
          .findAll();
      if (people.isEmpty) {
        return;
      }
      for (final FacePerson person in people) {
        person.name = toName;
      }
      await isar.facePersons.putAll(people);
    });
  }

  Future<AppSettings> getSettings() async {
    final existing = await isar.appSettings.get(0);
    if (existing != null) {
      return existing;
    }
    final settings = AppSettings();
    await isar.writeTxn(() async {
      await isar.appSettings.put(settings);
    });
    return settings;
  }

  Future<void> updateServerUrl(String url) async {
    final settings = await getSettings();
    settings.serverUrl = url;
    await isar.writeTxn(() async {
      await isar.appSettings.put(settings);
    });
  }
}

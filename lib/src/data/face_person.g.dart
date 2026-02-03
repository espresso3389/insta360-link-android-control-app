// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'face_person.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFacePersonCollection on Isar {
  IsarCollection<FacePerson> get facePersons => this.collection();
}

const FacePersonSchema = CollectionSchema(
  name: r'FacePerson',
  id: 1283850144865261502,
  properties: {
    r'boxH': PropertySchema(
      id: 0,
      name: r'boxH',
      type: IsarType.double,
    ),
    r'boxW': PropertySchema(
      id: 1,
      name: r'boxW',
      type: IsarType.double,
    ),
    r'boxX': PropertySchema(
      id: 2,
      name: r'boxX',
      type: IsarType.double,
    ),
    r'boxY': PropertySchema(
      id: 3,
      name: r'boxY',
      type: IsarType.double,
    ),
    r'createdAt': PropertySchema(
      id: 4,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'faceEmbedding': PropertySchema(
      id: 5,
      name: r'faceEmbedding',
      type: IsarType.doubleList,
    ),
    r'faceJpegBytes': PropertySchema(
      id: 6,
      name: r'faceJpegBytes',
      type: IsarType.byteList,
    ),
    r'name': PropertySchema(
      id: 7,
      name: r'name',
      type: IsarType.string,
    )
  },
  estimateSize: _facePersonEstimateSize,
  serialize: _facePersonSerialize,
  deserialize: _facePersonDeserialize,
  deserializeProp: _facePersonDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _facePersonGetId,
  getLinks: _facePersonGetLinks,
  attach: _facePersonAttach,
  version: '3.1.0+1',
);

int _facePersonEstimateSize(
  FacePerson object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.faceEmbedding;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  {
    final value = object.faceJpegBytes;
    if (value != null) {
      bytesCount += 3 + value.length;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _facePersonSerialize(
  FacePerson object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.boxH);
  writer.writeDouble(offsets[1], object.boxW);
  writer.writeDouble(offsets[2], object.boxX);
  writer.writeDouble(offsets[3], object.boxY);
  writer.writeDateTime(offsets[4], object.createdAt);
  writer.writeDoubleList(offsets[5], object.faceEmbedding);
  writer.writeByteList(offsets[6], object.faceJpegBytes);
  writer.writeString(offsets[7], object.name);
}

FacePerson _facePersonDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FacePerson();
  object.boxH = reader.readDoubleOrNull(offsets[0]);
  object.boxW = reader.readDoubleOrNull(offsets[1]);
  object.boxX = reader.readDoubleOrNull(offsets[2]);
  object.boxY = reader.readDoubleOrNull(offsets[3]);
  object.createdAt = reader.readDateTime(offsets[4]);
  object.faceEmbedding = reader.readDoubleList(offsets[5]);
  object.faceJpegBytes = reader.readByteList(offsets[6]);
  object.id = id;
  object.name = reader.readString(offsets[7]);
  return object;
}

P _facePersonDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDoubleOrNull(offset)) as P;
    case 1:
      return (reader.readDoubleOrNull(offset)) as P;
    case 2:
      return (reader.readDoubleOrNull(offset)) as P;
    case 3:
      return (reader.readDoubleOrNull(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    case 5:
      return (reader.readDoubleList(offset)) as P;
    case 6:
      return (reader.readByteList(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _facePersonGetId(FacePerson object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _facePersonGetLinks(FacePerson object) {
  return [];
}

void _facePersonAttach(IsarCollection<dynamic> col, Id id, FacePerson object) {
  object.id = id;
}

extension FacePersonQueryWhereSort
    on QueryBuilder<FacePerson, FacePerson, QWhere> {
  QueryBuilder<FacePerson, FacePerson, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FacePersonQueryWhere
    on QueryBuilder<FacePerson, FacePerson, QWhereClause> {
  QueryBuilder<FacePerson, FacePerson, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension FacePersonQueryFilter
    on QueryBuilder<FacePerson, FacePerson, QFilterCondition> {
  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'boxH',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'boxH',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boxH',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boxH',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boxH',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxHBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boxH',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'boxW',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'boxW',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boxW',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boxW',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boxW',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxWBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boxW',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'boxX',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'boxX',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boxX',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boxX',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boxX',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxXBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boxX',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'boxY',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'boxY',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'boxY',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'boxY',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'boxY',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> boxYBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'boxY',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'faceEmbedding',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'faceEmbedding',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingElementEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'faceEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingElementGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'faceEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingElementLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'faceEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingElementBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'faceEmbedding',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceEmbeddingLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceEmbedding',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'faceJpegBytes',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'faceJpegBytes',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'faceJpegBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'faceJpegBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'faceJpegBytes',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'faceJpegBytes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition>
      faceJpegBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'faceJpegBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }
}

extension FacePersonQueryObject
    on QueryBuilder<FacePerson, FacePerson, QFilterCondition> {}

extension FacePersonQueryLinks
    on QueryBuilder<FacePerson, FacePerson, QFilterCondition> {}

extension FacePersonQuerySortBy
    on QueryBuilder<FacePerson, FacePerson, QSortBy> {
  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxH() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxH', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxHDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxH', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxW() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxW', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxWDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxW', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxX() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxX', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxXDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxX', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxY() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxY', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByBoxYDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxY', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension FacePersonQuerySortThenBy
    on QueryBuilder<FacePerson, FacePerson, QSortThenBy> {
  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxH() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxH', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxHDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxH', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxW() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxW', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxWDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxW', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxX() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxX', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxXDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxX', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxY() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxY', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByBoxYDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'boxY', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<FacePerson, FacePerson, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension FacePersonQueryWhereDistinct
    on QueryBuilder<FacePerson, FacePerson, QDistinct> {
  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByBoxH() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boxH');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByBoxW() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boxW');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByBoxX() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boxX');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByBoxY() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'boxY');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByFaceEmbedding() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'faceEmbedding');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByFaceJpegBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'faceJpegBytes');
    });
  }

  QueryBuilder<FacePerson, FacePerson, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }
}

extension FacePersonQueryProperty
    on QueryBuilder<FacePerson, FacePerson, QQueryProperty> {
  QueryBuilder<FacePerson, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FacePerson, double?, QQueryOperations> boxHProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boxH');
    });
  }

  QueryBuilder<FacePerson, double?, QQueryOperations> boxWProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boxW');
    });
  }

  QueryBuilder<FacePerson, double?, QQueryOperations> boxXProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boxX');
    });
  }

  QueryBuilder<FacePerson, double?, QQueryOperations> boxYProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'boxY');
    });
  }

  QueryBuilder<FacePerson, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<FacePerson, List<double>?, QQueryOperations>
      faceEmbeddingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'faceEmbedding');
    });
  }

  QueryBuilder<FacePerson, List<int>?, QQueryOperations>
      faceJpegBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'faceJpegBytes');
    });
  }

  QueryBuilder<FacePerson, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }
}

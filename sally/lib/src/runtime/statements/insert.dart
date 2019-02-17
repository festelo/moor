import 'package:meta/meta.dart';
import 'package:sally/sally.dart';
import 'package:sally/src/runtime/components/component.dart';

class InsertStatement<DataClass> {
  @protected
  final GeneratedDatabase database;
  @protected
  final TableInfo<dynamic, DataClass> table;

  InsertStatement(this.database, this.table);

  Future<void> insert(DataClass entity) async {
    if (!table.validateIntegrity(entity, true)) {
      throw InvalidDataException(
          'Invalid data: $entity cannot be written into ${table.$tableName}');
    }

    final map = table.entityToSql(entity)
      ..removeWhere((_, value) => value == null);

    final ctx = GenerationContext(database);
    ctx.buffer
      ..write('INSERT INTO ')
      ..write(table.$tableName)
      ..write(' (')
      ..write(map.keys.join(', '))
      ..write(') ')
      ..write('VALUES (');

    var first = true;
    for (var variable in map.values) {
      if (!first) {
        ctx.buffer.write(', ');
      }
      first = false;

      variable.writeInto(ctx);
    }

    ctx.buffer.write(')');

    await database.executor.doWhenOpened((e) async {
      await database.executor.runInsert(ctx.sql, ctx.boundVariables);
      database.markTableUpdated(table.$tableName);
    });
  }

  // TODO insert multiple values

}

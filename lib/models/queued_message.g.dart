// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'queued_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QueuedMessageAdapter extends TypeAdapter<QueuedMessage> {
  @override
  final int typeId = 1;

  @override
  QueuedMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QueuedMessage(
      address: fields[0] as String,
      body: fields[1] as String,
      date: fields[2] as int,
      id: fields[3] as int,
      queuedAt: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, QueuedMessage obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.address)
      ..writeByte(1)
      ..write(obj.body)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.id)
      ..writeByte(4)
      ..write(obj.queuedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

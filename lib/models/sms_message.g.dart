// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sms_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SmsMessageAdapter extends TypeAdapter<SmsMessage> {
  @override
  final int typeId = 0;

  @override
  SmsMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SmsMessage(
      address: fields[0] as String,
      body: fields[1] as String,
      date: fields[2] as int,
      id: fields[3] as int,
      isSpam: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SmsMessage obj) {
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
      ..write(obj.isSpam);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

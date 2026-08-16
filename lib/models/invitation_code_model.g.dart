// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invitation_code_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InvitationCodeAdapter extends TypeAdapter<InvitationCode> {
  @override
  final int typeId = 10;

  @override
  InvitationCode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InvitationCode(
      code: fields[0] as String,
      createdAt: fields[1] as DateTime,
      usedBy: fields[2] as String?,
      usedAt: fields[3] as DateTime?,
      createdBy: fields[4] as String?,
      expiresAt: fields[5] as DateTime?,
      maxUses: fields[6] as int,
      currentUses: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, InvitationCode obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.code)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.usedBy)
      ..writeByte(3)
      ..write(obj.usedAt)
      ..writeByte(4)
      ..write(obj.createdBy)
      ..writeByte(5)
      ..write(obj.expiresAt)
      ..writeByte(6)
      ..write(obj.maxUses)
      ..writeByte(7)
      ..write(obj.currentUses);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvitationCodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

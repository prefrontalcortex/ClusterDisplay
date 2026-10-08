# Wire-Format – Vorlage

Als Ausgangspunkt gedacht; an das bestehende Protokoll anpassen, wenn Kompatibilität nötig ist.

## Header (20 Byte)

| Offset | Typ | Feld |
|---|---|---|
| 0 | uint32 | Magic (`0x43445359`, "CDSY") |
| 4 | uint16 | Protokollversion |
| 6 | uint16 | Nachrichtentyp |
| 8 | uint64 | Framenummer |
| 16 | uint32 | Payload-Länge in Byte |

## Beispiel

```csharp
using System;
using System.Buffers.Binary;
using System.Runtime.InteropServices;

public enum MessageType : ushort { FrameState = 1, RepeaterReady = 2, Heartbeat = 3 }

public readonly struct PacketHeader
{
    public const uint Magic = 0x43445359;
    public const ushort CurrentVersion = 1;
    public const int Size = 20;

    public readonly ushort Version;
    public readonly MessageType Type;
    public readonly ulong Frame;
    public readonly uint PayloadLength;

    public PacketHeader(MessageType type, ulong frame, uint payloadLength)
    { Version = CurrentVersion; Type = type; Frame = frame; PayloadLength = payloadLength; }

    PacketHeader(ushort v, MessageType t, ulong f, uint len)
    { Version = v; Type = t; Frame = f; PayloadLength = len; }

    public void Write(Span<byte> dst)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(dst, Magic);
        BinaryPrimitives.WriteUInt16LittleEndian(dst.Slice(4), Version);
        BinaryPrimitives.WriteUInt16LittleEndian(dst.Slice(6), (ushort)Type);
        BinaryPrimitives.WriteUInt64LittleEndian(dst.Slice(8), Frame);
        BinaryPrimitives.WriteUInt32LittleEndian(dst.Slice(16), PayloadLength);
    }

    public static bool TryRead(ReadOnlySpan<byte> src, out PacketHeader h)
    {
        h = default;
        if (src.Length < Size) return false;
        if (BinaryPrimitives.ReadUInt32LittleEndian(src) != Magic) return false;
        h = new PacketHeader(
            BinaryPrimitives.ReadUInt16LittleEndian(src.Slice(4)),
            (MessageType)BinaryPrimitives.ReadUInt16LittleEndian(src.Slice(6)),
            BinaryPrimitives.ReadUInt64LittleEndian(src.Slice(8)),
            BinaryPrimitives.ReadUInt32LittleEndian(src.Slice(16)));
        return src.Length - Size >= h.PayloadLength;
    }
}

// Payload: nur blittable Felder, festes Layout.
[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct FrameState
{
    public double Time;
    public float DeltaTime;
    public UnityEngine.Random.State RandomState; // blittable (4 ints)
    public InputSnapshot Input;                  // eigenes blittable struct
}
```

Blittable Structs können mit `MemoryMarshal.Write(span, ref value)` / `MemoryMarshal.Read<T>(span)` geschrieben werden. Das ist nur dann endianness-sicher, wenn alle Nodes dieselbe Architektur haben (praktisch immer x64/ARM64 Little-Endian) – im Header trotzdem explizit bleiben, weil er versionsübergreifend lesbar sein muss.

## Größenbudget

UDP-Payload unter ~1400 Byte halten (typische MTU 1500 minus IP/UDP-Header), sonst IP-Fragmentierung – ein verlorenes Fragment verliert das ganze Paket. Größere Custom-Daten aufteilen oder Delta-kodieren.

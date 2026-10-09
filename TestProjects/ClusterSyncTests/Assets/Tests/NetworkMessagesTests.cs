using System;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using NUnit.Framework;

namespace Unity.ClusterDisplay.Tests
{
    /// <summary>
    /// Tests that apply to every network message (struct with a <see cref="MessageTypeAttribute"/>), so that a message
    /// added or changed later is covered automatically.
    /// </summary>
    public class NetworkMessagesTests
    {
        static (Type type, MessageTypeAttribute attribute)[] AllMessages => MessageTypeAttribute.AllTypes;

        [Test]
        public void EveryMessageTypeHasExactlyOneStruct()
        {
            var messageTypes = Enum.GetValues(typeof(MessageType)).Cast<MessageType>().Where(t => t != MessageType.None);
            foreach (var messageType in messageTypes)
            {
                var structs = AllMessages.Where(m => m.attribute.Type == messageType).Select(m => m.type.Name).ToArray();
                Assert.That(structs.Length, Is.EqualTo(1), $"{messageType} is used by: [{string.Join(", ", structs)}]");
            }
        }

        [Test]
        public void MessageTypeValuesAreStable()
        {
            // The numeric values are part of the wire format (a byte in the datagram header): never reorder or
            // renumber, only append (and increment UdpAgent.ProtocolVersion).
            var expected = new[]
            {
                "None", "RegisteringWithEmitter", "RepeaterRegistered", "FrameData", "RetransmitFrameData",
                "RepeaterWaitingToStartFrame", "EmitterWaitingToStartFrame", "PropagateQuit", "QuitReceived",
                "QuadroBarrierWarmupHeartbeat", "QuadroBarrierWarmupStatus", "SurveyRepeaters",
                "RepeatersSurveyAnswer", "RetransmitReceivedFrameData", "RetransmittedReceivedFrameData"
            };
            var actual = Enum.GetValues(typeof(MessageType)).Cast<MessageType>().OrderBy(t => (byte)t)
                .Select(t => t.ToString()).ToArray();
            Assert.That(actual, Is.EqualTo(expected));
            for (int i = 0; i < expected.Length; ++i)
            {
                Assert.That((byte)Enum.Parse(typeof(MessageType), expected[i]), Is.EqualTo(i));
            }
        }

        [Test]
        public void EveryMessageHasPackedSequentialLayout()
        {
            foreach (var (type, _) in AllMessages)
            {
                Assert.That(type.IsValueType, Is.True, type.Name);
                var layout = type.StructLayoutAttribute;
                Assert.That(layout, Is.Not.Null, type.Name);
                Assert.That(layout.Value, Is.EqualTo(LayoutKind.Sequential), type.Name);
                Assert.That(layout.Pack, Is.EqualTo(1), $"{type.Name} must use Pack = 1");
            }
        }

        [Test]
        public void EveryMessageFitsInADatagram()
        {
            // Smallest MTU we want to support is 1280 (minimum for IPv6), minus IP/UDP headers (28) and our header (3).
            const int k_Budget = 1280 - 28 - 3;
            foreach (var (type, _) in AllMessages)
            {
                Assert.That(Marshal.SizeOf(type), Is.LessThan(k_Budget / 2), $"{type.Name} leaves too little room for data");
            }
        }

        [Test]
        public void EveryMessageRoundtrips()
        {
            var method = typeof(NetworkMessagesTests).GetMethod(nameof(Roundtrip), BindingFlags.NonPublic | BindingFlags.Static);
            Assert.That(method, Is.Not.Null);
            foreach (var (type, _) in AllMessages)
            {
                method.MakeGenericMethod(type).Invoke(null, null);
            }
        }

        static void Roundtrip<T>() where T : unmanaged
        {
            var size = Marshal.SizeOf<T>();
            var random = new System.Random(42 + size);

            // Several patterns: all zeros, all ones and random bytes (covers extreme values of every field).
            var patterns = new byte[4][];
            for (int i = 0; i < patterns.Length; ++i)
            {
                patterns[i] = new byte[size];
            }
            for (int i = 0; i < size; ++i)
            {
                patterns[1][i] = 0xFF;
            }
            random.NextBytes(patterns[2]);
            random.NextBytes(patterns[3]);

            // Messages without any field (e.g. SurveyRepeaters) are only a signal, there is no data to compare.
            var hasData = typeof(T).GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).Length > 0;

            foreach (var pattern in patterns)
            {
                T original = MemoryMarshal.Read<T>(pattern);

                // Store at an offset (as done with the datagram header) in a bigger buffer, and read back.
                var buffer = new byte[size + 16];
                var written = original.StoreInBuffer(buffer.AsSpan(), 3);
                Assert.That(written, Is.EqualTo(size), typeof(T).Name);

                T loaded = ((ReadOnlySpan<byte>)buffer).LoadStruct<T>(3);
                var loadedBytes = new byte[size];
                MemoryMarshal.Write(loadedBytes, ref loaded);
                if (hasData)
                {
                    Assert.That(loadedBytes, Is.EqualTo(pattern), $"{typeof(T).Name} did not survive a roundtrip");
                }
            }

            // The buffer is too small
            if (hasData) Assert.Throws<ArgumentOutOfRangeException>(() =>
            {
                T value = default;
                value.StoreInBuffer(new byte[size - 1].AsSpan(), 0);
            }, typeof(T).Name);
        }
    }
}

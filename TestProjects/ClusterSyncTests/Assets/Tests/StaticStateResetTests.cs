using System;
using System.Collections.Generic;
using NUnit.Framework;
using Unity.ClusterDisplay.Utils;

namespace Unity.ClusterDisplay.Tests
{
    /// <summary>
    /// Static state must not leak from one play session to the next when entering play mode without domain reload.
    /// </summary>
    public class StaticStateResetTests
    {
        [TearDown]
        public void TearDown()
        {
            ServiceLocator.Withdraw<IClusterSyncState>(false);
        }

        [Test]
        public void StaleClusterSyncStateIsForgotten()
        {
            ServiceLocator.Provide<IClusterSyncState>(new StubClusterSyncState());
            Assert.That(ServiceLocator.TryGet<IClusterSyncState>(out _), Is.True);

            // What Unity does when entering the next play session
            ClusterSync.ResetStaticState();

            Assert.That(ServiceLocator.TryGet<IClusterSyncState>(out _), Is.False);
            Assert.That(ClusterDisplayState.GetIsActive(), Is.False);
        }

        class StubClusterSyncState : IClusterSyncState
        {
            public string InstanceName => "Stub";
            public NodeRole NodeRole => NodeRole.Emitter;
            public bool EmitterIsHeadless => false;
            public bool IsClusterLogicEnabled => true;
            public bool IsTerminated => false;
            public ulong Frame => 0;
            public byte NodeID => 0;
            public byte RenderNodeID { get; set; }
            public bool RepeatersDelayedOneFrame => false;
            public string GetDiagnostics() => "";
            public void ChangeClusterTopology(IReadOnlyList<ClusterTopologyEntry> entries) { }
            public void Terminate() { }
            public event Action OnNodeRoleChanged { add { } remove { } }
        }
    }
}

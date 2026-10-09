using System;
using System.Linq;
using System.Net;
#if ENABLE_INPUT_SYSTEM
using Unity.ClusterDisplay.Scripting;
#endif
using Unity.ClusterDisplay.Utils;
using UnityEngine;

#if UNITY_EDITOR
using UnityEditor;
#endif

namespace Unity.ClusterDisplay
{
    /// <summary>
    /// Need one and only one instance of this class in the scene.
    /// it's responsible for reading the config and applying it, then invoking the
    /// node logic each frame by injecting a call back in the player loop.
    /// </summary>
    public partial class ClusterSync
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void EnableClusterSyncOnLoad()
        {
            if (ClusterDisplaySettings.Current.EnableOnPlay)
            {
                EnableClusterSync();
            }
        }

        /// <summary>
        /// Forget everything that a previous play session left in static variables.
        /// </summary>
        /// <remarks>When entering play mode without domain reload (editor option), statics survive from one play
        /// session to the next.  A stale <see cref="IClusterSyncState"/> would be found by
        /// <see cref="EnableClusterSync"/> as an "existing instance" and cluster logic would never start again.
        /// </remarks>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        internal static void ResetStaticState()
        {
            ServiceLocator.Withdraw<IClusterSyncState>(false);
#if ENABLE_INPUT_SYSTEM
            ServiceLocator.Withdraw<InputSystemReplicator>(false);
            InputSystemReplicator.ResetStaticState();
#endif
        }

        static void EnableClusterSync()
        {
            if (ServiceLocator.TryGet<IClusterSyncState>(out var clusterSync))
            {
                ClusterDebug.Log($"Using existing ClusterSync instance {clusterSync.InstanceName}");
                return;
            }

            ClusterDebug.Log($"Creating instance of: {nameof(ClusterSync)} on demand.");

            var clusterSyncInstance = new ClusterSync();
            ServiceLocator.Provide<IClusterSyncState>(clusterSyncInstance);

            var clusterParams = ClusterDisplaySettings.Current.ClusterParams;

#if UNITY_EDITOR
            clusterParams.ClusterLogicSpecified = ClusterDisplaySettings.Current.EnableOnPlay;
            // Make sure we shut down cluster logic gracefully when we exit play mode
            EditorApplication.playModeStateChanged += OnPlayModeChanged;
            void OnPlayModeChanged(PlayModeStateChange playModeStateChange)
            {
                if (playModeStateChange is PlayModeStateChange.ExitingPlayMode)
                {
                    Debug.AssertFormat(ServiceLocator.TryGet(out clusterSync) && clusterSync == clusterSyncInstance,
                        "The active ClusterSync instance was changed. Unable to perform graceful shutdown.");

                    clusterSyncInstance.DisableClusterDisplay();
                    EditorApplication.playModeStateChanged -= OnPlayModeChanged;
                }
            }
#endif

            clusterSyncInstance.EnableClusterDisplay(clusterParams.PreProcess());
        }

        const string k_DefaultName = "DefaultClusterSync";
        public string InstanceName { get; }

        public ClusterSync (string instanceName = k_DefaultName)
        {
            InstanceName = instanceName;
            ClusterDebug.Log($"Created instance of: {nameof(ClusterSync)} with name: \"{instanceName}\".");
        }

        DebugPerf m_FrameRatePerf = new();
        DebugPerf m_StartDelayMonitor = new();
        DebugPerf m_EndDelayMonitor = new();

        public delegate void OnClusterDisplayStateChange();

        public static OnClusterDisplayStateChange onPreEnableClusterDisplay;
        public static OnClusterDisplayStateChange onPostEnableClusterDisplay;
        public static OnClusterDisplayStateChange onDisableCLusterDisplay;

        /// <summary>
        /// Returns the number of frames rendered by the Cluster Display.
        /// </summary>
        public UInt64 CurrentFrameID => LocalNode.FrameIndex;

        bool m_NewFrame;

        ClusterNode m_LocalNode;

        internal ClusterNode LocalNode
        {
            get => m_LocalNode;
            private set
            {
                if (!ReferenceEquals(value, m_LocalNode))
                {
                    NodeRole? previousRole = m_LocalNode?.NodeRole;
                    m_LocalNode = value;
                    NodeRole? newRole = m_LocalNode?.NodeRole;
                    if (previousRole.HasValue != newRole.HasValue ||
                        (newRole.HasValue && newRole.Value != previousRole.Value))
                    {
                        OnNodeRoleChanged?.Invoke();
                    }
                }
            }
        }

        internal NetworkStatistics CurrentNetworkStats => LocalNode.UdpAgent.Stats;

        /// <summary>
        /// Get the Node ID if cluster logic is enabled.
        /// </summary>
        /// <returns><see langword="true"/> if the cluster logic is enabled.</returns>
        public bool TryGetDynamicLocalNodeId(out byte dynamicLocalNodeId)
        {
            if (!IsClusterLogicEnabled)
            {
                dynamicLocalNodeId = 0;
                return false;
            }

            dynamicLocalNodeId = LocalNode.Config.NodeId;
            return true;
        }

        /// <summary>
        /// Debug info.
        /// </summary>
        /// <returns>Returns generic statistics as a string (Average FPS, AvgSynchronization overhead)</returns>
        public string GetDiagnostics()
        {
            if (LocalNode == null)
            {
                return string.Empty;
            }

            var quadroSyncState = GfxPluginQuadroSyncSystem.FetchState();
            return $"Cluster Sync Instance: {InstanceName},\r\n" +
				   $"Frame Stats:\r\n{LocalNode.GetDebugString(LocalNode.UdpAgent.Stats)}" +
                   $"\r\n\r\n\tAverage Frame Time: {(m_FrameRatePerf.Average * 1000)} ms" +
                   $"\r\n\tAverage Sync Overhead Time: {(m_StartDelayMonitor.Average + m_EndDelayMonitor.Average) * 1000} ms" +
                   $"\r\n\r\n Quadro Sync State:" +
                   $"\r\n\tInitialization: " + quadroSyncState.InitializationState.ToDescriptiveText() +
                   $"\r\n\tSwap group / barrier identifier: {quadroSyncState.SwapGroupId} / {quadroSyncState.SwapBarrierId}" +
                   $"\r\n\tPresent success / failure: {quadroSyncState.PresentedFramesSuccess} / {quadroSyncState.PresentedFramesFailure}";
        }

        void InstanceLog(string msg) => ClusterDebug.Log($"[{nameof(ClusterSync)} instance \"{InstanceName}\"]: {msg}");

        void RegisterDelegates()
        {
            UnRegisterDelegates();

            // Register Do(X) methods with ClusterSyncLooper network fences.
            ClusterSyncLooper.onInstanceDoPreFrame += PreFrame;
            ClusterSyncLooper.onInstanceDoFrame += DoFrame;
            ClusterSyncLooper.onInstancePostFrame += PostFrame;
            ClusterSyncLooper.onInstanceDoLateFrame += DoLateFrame;
        }

        void UnRegisterDelegates()
        {
            ClusterSyncLooper.onInstanceDoPreFrame -= PreFrame;
            ClusterSyncLooper.onInstanceDoFrame -= DoFrame;
            ClusterSyncLooper.onInstancePostFrame -= PostFrame;
            ClusterSyncLooper.onInstanceDoLateFrame -= DoLateFrame;
        }

        public void EnableClusterDisplay(ClusterParams clusterParams)
        {
            if (IsClusterLogicEnabled)
                return;

            InstanceLog($"Enabling {nameof(ClusterSync)}.");

#if UNITY_EDITOR
            if (!EditorApplication.isPlayingOrWillChangePlaymode)
                return;
#endif

            Application.targetFrameRate = clusterParams.TargetFps;

            IsTerminated = false;
            IsClusterLogicEnabled = clusterParams.ClusterLogicSpecified;
            EmitterIsHeadless = clusterParams.HeadlessEmitter;

            onPreEnableClusterDisplay?.Invoke();

            if (!IsClusterLogicEnabled)
            {
                InstanceLog("ClusterRendering is missing command line configuration. Will be dormant.");
                return;
            }

            if (!TryInitialize(clusterParams))
            {
                IsClusterLogicEnabled = false;
                return;
            }
            EnableTimeSync(clusterParams);

#if UNITY_STANDALONE_WIN
            if (NodeRole != NodeRole.Unassigned)
            {
                ClusterSyncWindowsHelpers.CheckNodeSetup();
            }
#endif

            RenderNodeID = LocalNode.Config.NodeId;
            if (clusterParams.ReplaceHeadlessEmitter && EmitterIsHeadless && NodeRole is NodeRole.Repeater)
            {
                --RenderNodeID;
            }
            if (NodeRole == NodeRole.Backup)
            {
                RenderNodeID = 0;
            }

            RegisterDelegates();
            ClusterSyncLooper.InjectSynchPointInPlayerLoop();
            onPostEnableClusterDisplay?.Invoke();
        }

        public void DisableClusterDisplay() => CleanUp();

        /// <summary>
        /// Fixed time step used by <see cref="TimeSync.FixedStep"/> when no <see cref="ClusterParams.TargetFps"/> is
        /// specified.
        /// </summary>
        const int k_DefaultFixedStepFramerate = 60;

        /// <summary>
        /// Is <see cref="Time.captureFramerate"/> currently set by us (<see cref="TimeSync.FixedStep"/>)?
        /// </summary>
        bool m_FixedStepTimeActive;

        void EnableTimeSync(ClusterParams clusterParams)
        {
            // In FixedStep mode the time of the engine is not sent over the network (see TimeSync.FixedStep).
            EmitterStateWriter.SynchronizeEngineTime = clusterParams.TimeSync != TimeSync.FixedStep;

            if (clusterParams.TimeSync == TimeSync.FixedStep)
            {
                var framerate = clusterParams.TargetFps;
                if (framerate <= 0)
                {
                    framerate = k_DefaultFixedStepFramerate;
                    ClusterDebug.LogWarning($"{nameof(TimeSync)}.{nameof(TimeSync.FixedStep)} needs a Target Fps (the " +
                        $"refresh rate of the displays), using {framerate}.");
                }

                // Remark: Must be set before the first frame, every node then goes through exactly the same sequence
                // of time values.
                Time.captureFramerate = framerate;
                m_FixedStepTimeActive = true;
                InstanceLog($"Time is synchronized using a fixed time step of 1/{framerate} s.");
            }
        }

        void DisableTimeSync()
        {
            EmitterStateWriter.SynchronizeEngineTime = true;
            if (m_FixedStepTimeActive)
            {
                m_FixedStepTimeActive = false;
                Time.captureFramerate = 0;
            }
        }

        bool TryInitializeEmitter(ClusterNodeConfig clusterNodeConfig, UdpAgentConfig udpConfig,
            ClusterParams clusterParams)
        {
            InstanceLog($"Initializing {nameof(ClusterSync)} for emitter.");
            try
            {
                var emitterNodeConfig = new EmitterNodeConfig
                {
                    ExpectedRepeaterCount = (byte)(clusterParams.RepeaterCount + clusterParams.BackupCount)
                };
                udpConfig.ReceivedMessagesType = EmitterNode.ReceiveMessageTypes.ToArray();
                LocalNode = new EmitterNode(clusterNodeConfig, emitterNodeConfig, new UdpAgent(udpConfig));

                InitializeEmitterInputSync(clusterNodeConfig);

                return true;
            }
            catch (Exception e)
            {
                ClusterDebug.LogError($"Cannot initialize emitter node: {e.Message}");
                return false;
            }
        }

        bool TryInitializeRepeater(ClusterNodeConfig clusterNodeConfig, UdpAgentConfig udpConfig)
        {
            InstanceLog($"Initializing {nameof(ClusterSync)} for repeater.");

            try
            {
                udpConfig.ReceivedMessagesType = RepeaterNode.ReceiveMessageTypes.ToArray();
                LocalNode = new RepeaterNode(clusterNodeConfig, new UdpAgent(udpConfig));

                InitializeRepeaterInputSync(clusterNodeConfig);

                return true;
            }
            catch (Exception e)
            {
                ClusterDebug.LogError($"Cannot initialize repeater node: {e.Message}");
                return false;
            }
        }

        bool TryInitializeBackup(ClusterNodeConfig clusterNodeConfig, UdpAgentConfig udpConfig)
        {
            InstanceLog($"Initializing {nameof(ClusterSync)} for backup.");

            try
            {
                udpConfig.ReceivedMessagesType = RepeaterNode.ReceiveMessageTypes.ToArray();
                LocalNode = new RepeaterNode(clusterNodeConfig, new UdpAgent(udpConfig), true);

                InitializeRepeaterInputSync(clusterNodeConfig);

                return true;
            }
            catch (Exception e)
            {
				ClusterDebug.LogError($"Cannot initialize backup node: {e.Message}");
                return false;
            }
        }

        static void InitializeEmitterInputSync(ClusterNodeConfig clusterNodeConfig)
        {
            switch (clusterNodeConfig.InputSync)
            {
#if ENABLE_INPUT_SYSTEM
                case InputSync.InputSystem:
                    ServiceLocator.Provide(new InputSystemReplicator(NodeRole.Emitter));
                    break;
#endif
                case InputSync.None:
                    break;
                default:
                    // Value that is not supported anymore (the legacy Input Manager, 2) or not available (Input
                    // System package not enabled): do not fail, input is just not synchronized.
                    ClusterDebug.LogWarning($"Input synchronization {clusterNodeConfig.InputSync} is not supported, " +
                        "inputs will not be synchronized.");
                    break;
            }
        }

        static void InitializeRepeaterInputSync(ClusterNodeConfig clusterNodeConfig)
        {
            switch (clusterNodeConfig.InputSync)
            {
#if ENABLE_INPUT_SYSTEM
                case InputSync.InputSystem:
                    ServiceLocator.Provide(new InputSystemReplicator(NodeRole.Repeater));
                    break;
#endif
                case InputSync.None:
                    break;
                default:
                    // Value that is not supported anymore (the legacy Input Manager, 2) or not available (Input
                    // System package not enabled): do not fail, input is just not synchronized.
                    ClusterDebug.LogWarning($"Input synchronization {clusterNodeConfig.InputSync} is not supported, " +
                        "inputs will not be synchronized.");
                    break;
            }
        }

        static void ClearRepeaterInputSync(ClusterNodeConfig clusterNodeConfig)
        {
            switch (clusterNodeConfig.InputSync)
            {
#if ENABLE_INPUT_SYSTEM
                case InputSync.InputSystem:
                    ServiceLocator.Withdraw<InputSystemReplicator>();
                    break;
#endif
                case InputSync.None:
                    break;
                default:
                    // Value that is not supported anymore (the legacy Input Manager, 2) or not available (Input
                    // System package not enabled): do not fail, input is just not synchronized.
                    ClusterDebug.LogWarning($"Input synchronization {clusterNodeConfig.InputSync} is not supported, " +
                        "inputs will not be synchronized.");
                    break;
            }
        }

        bool TryInitialize(ClusterParams clusterParams)
        {
            RepeatersDelayedOneFrame = clusterParams.DelayRepeaters;

            try
            {
                var nodeConfig = new ClusterNodeConfig
                {
                    NodeId = clusterParams.NodeID,
                    HandshakeTimeout = clusterParams.HandshakeTimeout,
                    CommunicationTimeout = clusterParams.CommunicationTimeout,
                    RepeatersDelayed = clusterParams.DelayRepeaters,
                    Fence = clusterParams.Fence,
                    InputSync = clusterParams.InputSync,
                    HasAtLeastOneBackupNode = clusterParams.BackupCount > 0
                };

                var udpAgentConfig = new UdpAgentConfig
                {
                    MulticastIp = IPAddress.Parse(clusterParams.MulticastAddress),
                    Port = clusterParams.Port,
                    AdapterName = clusterParams.AdapterName,
                    LoggingFilenameSuffix = $".NodeId-{clusterParams.NodeID}"
                };

                return clusterParams.Role switch
                {
                    NodeRole.Emitter => TryInitializeEmitter(nodeConfig, udpAgentConfig, clusterParams),
                    NodeRole.Repeater => TryInitializeRepeater(nodeConfig, udpAgentConfig),
                    NodeRole.Backup => TryInitializeBackup(nodeConfig, udpAgentConfig),
                    _ => throw new Exception("Cluster command arguments requires a \"-emitterNode\" or \"-node\" flag.")
                };
            }

            catch (Exception e)
            {
                ClusterDebug.LogError("Invalid command line arguments for configuring ClusterRendering.");
                ClusterDebug.LogException(e);

                CleanUp();
                return false;
            }
        }

        void TransitionBackupToEmitterNode()
        {
            // Prepare for the new node we will create
            Debug.Assert(LocalNode != null);
            var clusterNodeConfig = LocalNode.Config;
            clusterNodeConfig.FirstFrameIndex = LocalNode.FrameIndex;
            var udpAgent = LocalNode.UdpAgent.Clone(EmitterNode.ReceiveMessageTypes.ToArray());
            var localRepeaterNode = (RepeaterNode)LocalNode;

            EmitterNodeConfig emitterNodeConfig = new()
            {
                ExpectedRepeaterCount = (byte)LocalNode.UpdatedClusterTopology.Entries.Count(
                    e => e.NodeRole is NodeRole.Repeater or NodeRole.Backup),
                RepeatersSurveyResult =
                    localRepeaterNode.RepeatersSurveyResult.Where(a => a.NodeId != clusterNodeConfig.NodeId).ToArray()
            };

            // Get rid of the previous node
            LocalNode?.Dispose();
            LocalNode = null;
            ClearRepeaterInputSync(clusterNodeConfig);

            // Create the replacing emitter node.
            LocalNode = new EmitterNode(clusterNodeConfig, emitterNodeConfig, udpAgent);
            InitializeEmitterInputSync(clusterNodeConfig);
        }

        public void CleanUp()
        {
            IsClusterLogicEnabled = false;
            DisableTimeSync();

            LocalNode?.Dispose();
            LocalNode = null;

            ClusterSyncLooper.RemoveSynchPointFromPlayerLoop();

            UnRegisterDelegates();

#if ENABLE_INPUT_SYSTEM
            ServiceLocator.Withdraw<InputSystemReplicator>();
#endif

            onDisableCLusterDisplay?.Invoke();

            InstanceLog($"Flushed.");
        }

        void PreFrame ()
        {
            try
            {
                m_FrameRatePerf.SampleNow();
                m_FrameRatePerf.RefPoint();

                m_StartDelayMonitor.RefPoint();
            }

            catch (Exception e)
            {
                OnException(e);
            }

            finally
            {
                OnFinally();
            }
        }

        void DoFrame ()
        {
            try
            {
                var ret = LocalNode.DoFrame();
                if (ret == DoFrameResult.BackupToEmitter)
                {
                    TransitionBackupToEmitterNode();
                    LocalNode.DoFrame();
                }
            }

            catch (Exception e)
            {
                OnException(e);
            }

            finally
            {
                OnFinally();
            }
        }

        void PostFrame ()
        {
            try
            {
                LocalNode.ConcludeFrame();

                m_StartDelayMonitor.SampleNow();
            }

            catch (Exception e)
            {
                OnException(e);
            }

            finally
            {
                OnFinally();
            }
        }

        public void DoLateFrame ()
        {
            try
            {
                m_EndDelayMonitor.RefPoint();
                m_EndDelayMonitor.SampleNow();
            }

            catch (Exception e)
            {
                OnException(e);
            }

            finally
            {
                OnFinally();
            }
        }

        void OnException (Exception e)
        {
            Terminate();

            InstanceLog($"Encountered exception.");
            ClusterDebug.LogException(e);
        }

        void OnFinally ()
        {
            if (IsTerminated)
            {
                CleanUp();
            }
        }
    }
}

using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Unity.ClusterDisplay
{
    public static class ClusterDebug
    {
        [System.Diagnostics.Conditional("CLUSTER_DISPLAY_VERBOSE_LOGGING")]
        public static void Log (string msg) =>
            Debug.Log(msg);

        public static void LogWarning (string msg) =>
            Debug.LogWarning(msg);

        public static void LogError (string msg) =>
            Debug.LogError(msg);

        public static void LogException (System.Exception exception) =>
            Debug.LogException(exception);

        // Formatted error logging helper. Useful when building diagnostic messages.
        public static void LogErrorFormat(string format, params object[] args) =>
            Debug.LogError(string.Format(format, args));

        // Dump a set of command-line arguments (or similar) to the log for debugging.
        public static void LogArgs(string prefix, IEnumerable<string> args)
        {
            if (args == null)
            {
                Debug.LogFormat("{0}: <null>", prefix);
                return;
            }

            Debug.LogFormat("{0}: {1}", prefix, string.Join(", ", args));
        }

        public static void Assert (bool assertion, string msg)
        {
            Debug.Assert(assertion, msg);
        }
    }
}
